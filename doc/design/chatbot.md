# Large-Scale Chatbot Application Design

Design for a conversational AI application like ChatGPT or Claude.ai.

---

## Scenario

### Core Use Cases

1. User sends a message, receives a streamed AI response
2. User manages conversations (create, list, rename, delete)
3. User views conversation history
4. Multi-turn context: each message includes prior conversation context
5. File/image upload and processing
6. User authentication and session management

### Constraints

| Metric | Estimate |
|--------|----------|
| DAU | 50M |
| Avg conversations/user/day | 3 |
| Avg user turns/conversation | 10 |
| Peak user-turn QPS (`POST /v1/chat/messages`) | 50K |
| Stored message rows per user turn | 2 (user row + assistant row) |
| Peak concurrent response streams | 250K-1.5M (50K turns/s × 5-30s stream duration) |
| Avg input tokens/user turn | 2K |
| Avg output tokens/user turn | 500 |
| Avg response latency (streaming first token) | < 500ms |
| Avg response latency (full generation) | 5-30s |
| Message read:write ratio | 3:1 (history reads vs user turns) |
| Storage per stored message row (avg, incl. metadata) | ~4KB |
| Daily new user turns | 1.5B |
| Daily stored message rows | 3.0B |
| Daily storage growth | ~12TB |

### Non-Functional Requirements

- Streaming responses (Server-Sent Events / WebSocket)
- Idempotent send semantics with exactly-once persistence per `client_request_id`
- Graceful degradation under GPU capacity pressure
- Multi-region availability
- Rate limiting per user and per organization

---

## Service

### High-Level Architecture

```
┌──────────────┐
│   Frontend   │
│  (React SPA) │
└──────┬───────┘
       │ HTTPS
┌──────▼───────┐
│     CDN      │
│ (CloudFront) │
└──────┬───────┘
       │
┌──────▼───────┐     ┌──────────────┐
│   API GW /   │────►│  Auth Service│
│ Load Balancer│     └──────────────┘
└──────┬───────┘
       │
┌──────▼───────────────────────────────────┐
│            Web Service Layer             │
│  ┌─────────────┐  ┌──────────────────┐   │
│  │ Chat Service│  │Conversation Svc  │   │
│  └──────┬──────┘  └────────┬─────────┘   │
│         │                  │             │
│  ┌──────▼──────┐  ┌───────▼──────────┐   │
│  │  Inference  │  │  Storage Service  │   │
│  │   Gateway   │  │                  │   │
│  └──────┬──────┘  └──────────────────┘   │
└─────────┼────────────────────────────────┘
          │
┌─────────▼────────────────────────────────┐
│          Inference Layer                 │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│  │ GPU Pool │ │ GPU Pool │ │ GPU Pool │ │
│  │ (Warm)   │ │ (Warm)   │ │ (Cold)   │ │
│  └──────────┘ └──────────┘ └──────────┘ │
└──────────────────────────────────────────┘
```

### Frontend

| Component | Technology | Purpose |
|-----------|-----------|---------|
| SPA | React / Next.js | Main application shell |
| Streaming UI | SSE via `fetch` + `ReadableStream` | Token-by-token response rendering |
| State management | React context + SWR | Conversation list, message cache |
| Markdown rendering | `react-markdown` + syntax highlighting | Format AI responses |
| CDN | CloudFront / Cloudflare | Static assets, edge caching |

Key design decisions:
- **Optimistic UI**: append a local pending user message immediately, then reconcile with server-assigned message IDs
- **Streaming**: use SSE (`text/event-stream`) over WebSocket for simplicity and HTTP/2 compatibility
- **Reconnection**: if stream drops mid-response, retry the same `client_request_id` with `Last-Event-ID`; server replays buffered events or returns the finalized assistant message
- **Conversation sidebar**: paginated list, loaded on demand (not all conversations upfront)

### Streaming Protocol: Server-Sent Events (SSE)

SSE is a standard HTTP protocol where the server pushes data to the client over a long-lived connection. The client opens a regular HTTP request, and the server responds with `Content-Type: text/event-stream`, sending chunks as they become available.

#### Why SSE over WebSocket

| | SSE | WebSocket |
|--|-----|-----------|
| Direction | Server → Client (unidirectional) | Bidirectional |
| Protocol | Standard HTTP | Upgrade from HTTP |
| Load balancer support | Works with any HTTP LB / CDN | Requires sticky sessions or WS-aware LB |
| Reconnection | Built-in via `EventSource` API | Manual reconnect logic required |
| HTTP/2 multiplexing | Yes — shares connection with other requests | No — separate TCP connection |
| Complexity | Simple — just HTTP | Higher — connection lifecycle, ping/pong |

For a chatbot, the user sends messages via normal `POST` requests and only the response needs streaming — SSE fits this unidirectional pattern naturally.

#### SSE Message Flow

```
Client                        Server
  │                              │
  │  POST /v1/chat/messages      │
  │  Content-Type: application/json
  │  {"content": "Hi",           │
  │   "client_request_id":"req_1"}│
  │─────────────────────────────►│
  │                              │
  │  HTTP/2 200                  │
  │  Content-Type: text/event-stream
  │◄─────────────────────────────│
  │                              │
  │  id: 0                       │
  │  event: message_start        │
  │  data: {"assistant_message_id":"msg_1"}
  │◄─────────────────────────────│
  │                              │
  │  id: 1                       │
  │  event: token                │
  │  data: {"text":"Hello"}      │
  │◄─────────────────────────────│
  │                              │
  │  id: 2                       │
  │  event: token                │
  │  data: {"text":"!"}          │
  │◄─────────────────────────────│
  │                              │
  │  id: 3                       │
  │  event: done                 │
  │  data: {"message_id":"msg_1"}│
  │◄─────────────────────────────│
  │                              │
  │  (connection closed)         │
  │                              │
```

#### Event Types

| Event | Payload | Purpose |
|-------|---------|---------|
| `message_start` | `{"assistant_message_id": "..."}` | Announces the durable placeholder row for the assistant reply |
| `token` | `{"text": "...", "index": N}` | Incremental token for real-time rendering |
| `thinking` | `{"text": "..."}` | Model reasoning (shown in collapsible UI) |
| `error` | `{"code": "rate_limited", "retry_after": 30}` | Graceful error mid-stream |
| `done` | `{"message_id": "...", "usage": {...}}` | Final event — signals completion |

#### Client Implementation

```javascript
async function streamChat(conversationId, content, clientRequestId, lastEventId) {
  const response = await fetch('/v1/chat/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
      ...(lastEventId ? { 'Last-Event-ID': lastEventId } : {}),
    },
    body: JSON.stringify({
      conversation_id: conversationId,
      client_request_id: clientRequestId,
      content,
    }),
  });

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let event = { id: null, type: 'message' };

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop();

    for (const line of lines) {
      if (line.startsWith('id: ')) {
        event.id = line.slice(4);
      } else if (line.startsWith('event: ')) {
        event.type = line.slice(7);
      } else if (line.startsWith('data: ')) {
        const payload = JSON.parse(line.slice(6));
        onEvent(event.type, payload);  // append to UI
        if (event.id) lastEventId = event.id;
        event = { id: null, type: 'message' };
      }
    }
  }
}
```

Uses `fetch` + `ReadableStream` instead of the browser `EventSource` API because `EventSource` only supports GET requests — chat requires POST with a JSON body. The client tracks the latest SSE `id` and replays with `Last-Event-ID` on retry.

#### Reconnection and Reliability

- Each SSE event carries a monotonically increasing `id`
- Client retries the same `client_request_id` and sends `Last-Event-ID` so the server can replay missing events
- Server deduplicates on `(conversation_id, client_request_id)` and either reattaches to the in-flight generation or returns the finalized persisted assistant message
- Streaming deltas are buffered in a short-lived replay store (for example Redis Streams) until the final assistant message is committed
- Client-side timeout: if no token received for 30s, abort and show retry button

### Web Services

#### API Gateway

- TLS termination, request routing
- Rate limiting: token bucket per user (e.g., 60 messages/hour free tier, 600/hour paid)
- Request validation and sanitization
- Authentication via JWT (short-lived access token + refresh token)

#### Chat Service

The core service handling message send/receive:

```
POST /v1/chat/messages
{
  "conversation_id": "conv_abc123",
  "client_request_id": "req_7f3c9d8a",
  "content": "Explain quicksort",
  "attachments": [{"attachment_id": "att_123"}]
}

Response: SSE stream
id: 0
event: message_start
data: {"assistant_message_id": "msg_xyz", "status": "streaming"}

id: 1
event: token
data: {"text": "Quick", "index": 0}

id: 2
event: token
data: {"text": "sort", "index": 1}

...

id: 99
event: done
data: {"message_id": "msg_xyz", "usage": {"input_tokens": 45, "output_tokens": 312}}
```

Flow:
1. Authenticate request, check rate limits
2. Use `(conversation_id, client_request_id)` as an idempotency key; if it already exists, resume or replay the prior result instead of creating a duplicate turn
3. In a single transaction, persist the user message and an assistant placeholder row with `status=streaming`
4. Assemble prompt context from the current turn, a recent-message window, and the latest summary checkpoint
5. Submit to inference gateway, stream tokens back, and append deltas to a short-lived replay buffer
6. On completion, finalize the assistant row (`status=completed`, usage, full content) and update conversation metadata; on failure, mark it `failed`

#### Context Management

Do not load the entire conversation into every prompt. Instead:
- Always include the system prompt, conversation settings, and the active branch's most recent messages
- Maintain rolling summary checkpoints every N turns (for example every 20 turns) and include the latest summary when the full thread no longer fits
- Reserve token budget up front for tool calls and model output; trim oldest raw turns first
- Rehydrate older messages or attachment extracts only when they are referenced or retrieved as relevant context

This keeps prompt-building latency roughly bounded even as conversations grow to hundreds or thousands of turns.

#### Attachment Processing

Attachments need a separate ingestion path from chat sends:
1. Client calls `POST /v1/uploads` to obtain a presigned upload URL and `attachment_id`
2. Client uploads the raw file directly to S3/GCS
3. An async media pipeline validates MIME type and size, scans for malware, extracts OCR/text/thumbnails, and marks the attachment `ready`
4. `POST /v1/chat/messages` can only reference attachments in `ready` state
5. Prompt assembly passes normalized text, image references, or both to the inference gateway

Large documents should be chunked during processing so prompt assembly can retrieve only relevant sections instead of inlining the whole file.

#### Conversation Service

CRUD operations for conversations:
- `GET /v1/conversations` — paginated list (cursor-based)
- `POST /v1/conversations` — create new
- `PATCH /v1/conversations/:id` — rename, archive
- `DELETE /v1/conversations/:id` — soft delete
- `GET /v1/conversations/:id/messages` — paginated message history

#### Inference Gateway

Sits between web services and GPU clusters:

```
┌──────────────┐
│ Chat Service │
└──────┬───────┘
       │ gRPC
┌──────▼───────────────────────┐
│      Inference Gateway       │
│  ┌────────────────────────┐  │
│  │ Admission Queue        │  │
│  │ (in-memory / Redis)    │  │
│  └───────────┬────────────┘  │
│  ┌───────────▼────────────┐  │
│  │   Scheduler / Router   │  │
│  │  - Model selection     │  │
│  │  - Capacity routing    │  │
│  │  - Priority queuing    │  │
│  └───────────┬────────────┘  │
│  ┌───────────▼────────────┐  │
│  │   Inference Workers    │  │
│  │  (vLLM / TensorRT-LLM)│  │
│  └────────────────────────┘  │
└──────────────────────────────┘
```

Responsibilities:
- **Admission queueing**: hold a short backlog when GPU capacity is briefly saturated
- **Continuous batching**: group multiple requests into a single GPU batch for throughput (vLLM)
- **KV cache management**: reuse cached prefixes for system prompts and repeated context
- **Model routing**: route to appropriate model variant (small/large) based on user tier
- **Failover**: retry on different GPU pool if a node fails mid-generation
- **Token budget enforcement**: cap max output tokens per request

#### Queueing Strategy: Kafka vs Low-Latency Admission Queue

For interactive chat, the queue on the hot path is primarily an admission-control mechanism, not a long-term job buffer.

| Option | Strengths | Weaknesses | Best fit |
|--------|-----------|------------|----------|
| Kafka on hot path | Durable backlog, replay, strong decoupling between chat and inference, good for absorbing long bursts | Extra broker hop, replication/consumer lag, higher cost and operational overhead, harder to keep first-token latency predictable | Offline inference, batch summarization, non-interactive retries |
| In-memory gateway queue | Lowest latency, simplest scheduler integration, cheapest to operate, easy to batch directly against live GPU capacity | Queue state is lost if the gateway dies, backlog can only be short, needs idempotent retries from the caller | Real-time chat with tight first-token SLO |
| Redis Streams / NATS JetStream | Lower latency and lower operational cost than Kafka, some durability and replay, simpler multi-consumer coordination | Still adds a network hop, less suitable than in-memory for sub-second scheduling, less durable / lower ecosystem maturity than Kafka | Short-lived buffering when multiple gateway replicas must share queue state |

Recommended approach:
- Keep the real-time chat path on an in-memory admission queue inside the inference gateway, optionally mirrored to Redis Streams when multiple gateway replicas need a shared short backlog
- Use Kafka only for asynchronous workloads: summarization, analytics fan-out, batch embedding/indexing, and deferred retries after the user-facing request has already failed or been downgraded
- Cap hot-path queue wait aggressively (for example target under 1-2 seconds); if expected wait exceeds the SLO, route to a smaller model, return a retryable overload error, or place the work onto an async queue

This balances latency and cost:
- Latency stays low because the scheduler can dispatch directly against live GPU availability without broker round-trips
- Cost stays lower because Kafka clusters are only needed for workloads that benefit from durable buffering and replay
- Reliability remains acceptable because the source of truth is the persisted turn in PostgreSQL plus `client_request_id`-based retries, not the transient scheduler queue

---

## Storage

### Data Model

```
┌─────────────────────────┐       ┌─────────────────────────────┐
│         users           │       │       conversations          │
├─────────────────────────┤       ├─────────────────────────────┤
│ user_id (PK)        UUID│───┐   │ conversation_id (PK)    UUID│
│ email             string│   │   │ user_id (FK)            UUID│
│ name              string│   └──►│ title                 string│
│ tier        enum(free,  │       │ model                 string│
│             pro, team)  │       │ created_at         timestamp│
│ created_at     timestamp│       │ updated_at         timestamp│
│ rate_limit_override  int│       │ is_deleted            boolean│
└─────────────────────────┘       └──────────────┬──────────────┘
                                                 │
                                  ┌──────────────▼──────────────┐
                                  │          messages            │
                                  ├─────────────────────────────┤
                                  │ message_id (PK)         UUID│
                                  │ conversation_id (FK)    UUID│
                                  │ role    enum(user,assistant) │
                                  │ client_request_id   string? │
                                  │ status enum(streaming,      │
                                  │        completed,failed)?   │
                                  │ content                 text│
                                  │ token_count              int│
                                  │ model                 string│
                                  │ created_at         timestamp│
                                  │ completed_at       timestamp│
                                  │ parent_message_id      UUID │
                                  └──────────────┬──────────────┘
                                                 │
                                  ┌──────────────▼──────────────┐
                                  │         attachments          │
                                  ├─────────────────────────────┤
                                  │ attachment_id (PK)      UUID│
                                  │ conversation_id (FK)    UUID│
                                  │ message_id (FK)        UUID?│
                                  │ object_key            string│
                                  │ mime_type             string│
                                  │ size_bytes               int│
                                  │ status enum(uploading,     │
                                  │        scanning,ready,     │
                                  │        failed)             │
                                  │ extracted_text         text │
                                  │ created_at         timestamp│
                                  └─────────────────────────────┘
```

`parent_message_id` enables branching (edit a prior message and fork the conversation). Store `client_request_id` on the assistant placeholder row (or a separate turn table) and enforce a partial unique index on `(conversation_id, client_request_id)` for those rows so retried sends map back to the same durable turn instead of inserting duplicates.

### Storage Layer Selection

| Data | Store | Justification |
|------|-------|---------------|
| Users, conversations, messages | PostgreSQL (sharded by user_id) | Relational integrity, strong consistency for user-facing data |
| Session tokens | Redis | Fast expiry-based lookups, ephemeral |
| Rate limit counters | Redis | Atomic increments, sliding window |
| Attachment metadata + processing state | PostgreSQL | Transactional ACLs, status transitions, linkage to messages |
| File blobs | S3 / GCS | Blob storage for images, documents |
| Conversation search | Elasticsearch | Full-text search across message content |
| Analytics / usage | ClickHouse | Columnar store for token usage, latency metrics |

### Sharding Strategy

Shard PostgreSQL by `user_id` (consistent hashing):
- All of a user's conversations and messages land on the same shard
- Queries are always scoped to a single user — no cross-shard joins needed
- 256 logical shards mapped to physical nodes, rebalance by moving logical shards

### Caching

```
Client ──► CDN (static assets)
       ──► API GW ──► Redis Cache ──► PostgreSQL

Cache layers:
1. Conversation list    → Redis, 5min TTL, invalidate on write
2. Recent messages      → Redis, per-conversation, invalidate on new message
3. User profile/tier    → Redis, 15min TTL
```

---

## Scale

### Inference Scaling (the bottleneck)

GPU inference is the most expensive and constrained resource:

```
Peak output throughput:
50K user turns/s × 500 output tokens = 25M output tokens/sec

Peak input prefill throughput:
50K user turns/s × 2K input tokens = 100M input tokens/sec

Peak open streams:
50K user turns/s × 5-30s generation time = 250K-1.5M concurrent responses

Single H100 throughput (illustrative, continuous batching): ~5K output tokens/sec
Required H100s for steady-state decode throughput: ~5,000 GPUs

With prefill headroom, multi-region redundancy, and cold spare: ~7,000 GPUs across regions
```

Scaling strategies:
- **Continuous batching** (vLLM): dynamically batch requests to maximize GPU utilization
- **KV cache sharing**: common system prompts cached across requests, reducing prefill cost
- **Speculative decoding**: use small draft model to propose tokens, large model to verify — 2-3x speedup
- **Quantization**: INT8/FP8 inference reduces memory, fits larger batches per GPU
- **Multi-tier models**: route simple queries to smaller/faster models, complex to large models
- **Prefix caching**: cache KV state for system prompt — amortize across all requests
- **Admission control**: keep the interactive queue short; once predicted wait exceeds the first-token SLO, downgrade or reject rather than letting backlog grow unbounded

### Web Service Scaling

```
Size the web tier on concurrent open streams, not raw request QPS:

250K-1.5M concurrent SSE streams
÷ ~20K live streams/instance
= ~13-75 streaming web instances, plus headroom for deploys and spikes
```

- Stateless services behind load balancer, scale horizontally
- Split non-streaming API pods from streaming chat pods so long-lived SSE connections do not crowd out CRUD traffic
- Auto-scale on CPU and active connection count (SSE connections are long-lived)
- Connection draining: wait for active streams to complete before terminating instance

### Database Scaling

```
Per 50K user turns/sec:
- 50K user-message inserts/sec
- 50K assistant placeholder inserts/sec
- 50K assistant completion updates/sec

Logical new rows: 100K rows/sec
Logical data growth: 100K × 4KB = ~400MB/sec
History / sidebar reads: ~150K QPS (3:1 read:write vs user turns)
```

- PostgreSQL with 32 shards handles write throughput
- Read replicas per shard for read scaling
- Redis absorbs hot-path reads (conversation list, recent messages, replay buffers)
- Archive messages older than 1 year to cold storage (S3 + Parquet) with on-demand rehydration

### Multi-Region

```
┌─────────┐     ┌─────────┐     ┌─────────┐
│ US-East │     │ EU-West │     │ AP-SE   │
│         │     │         │     │         │
│ Web+DB  │◄───►│ Web+DB  │◄───►│ Web+DB  │
│ GPU Pool│     │ GPU Pool│     │ GPU Pool│
└─────────┘     └─────────┘     └─────────┘
     ▲               ▲               ▲
     └───── Global DNS (latency-based routing) ─────┘
```

- Each region has independent web, database, and GPU pools
- User data is region-pinned (GDPR compliance for EU)
- Cross-region GPU overflow: if one region is GPU-saturated, route inference to another region (adds latency but avoids queue buildup)

### Reliability

| Failure | Mitigation |
|---------|------------|
| GPU node dies mid-generation | Inference gateway retries on a different node when possible; client retries with the same `client_request_id` + `Last-Event-ID`, and the server replays buffered events or returns the persisted partial/final state |
| Database shard down | Promote read replica to primary (automated failover) |
| Redis down | If Redis is only used for replay buffers / shared admission state, fall back to local in-memory queues and database reads; slightly lower resiliency but the chat path still works |
| Full region outage | DNS failover to nearest region; user data replicated async |
| GPU capacity exhausted | Queue with estimated wait time shown to user; prioritize paid tier |

### Cost Optimization

- Spot/preemptible GPU instances for non-real-time workloads (batch summarization)
- Tiered rate limits: free users get smaller model + lower rate, paid users get full model
- KV cache compression: reduce GPU memory per request, fit more concurrent requests
- Off-peak GPU scaling: scale down GPU pools during low-traffic hours
- Retry deduplication: repeated `POST /v1/chat/messages` with the same `client_request_id` reuse the in-flight stream or cached final result
