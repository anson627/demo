
KWOK_NODES=1
for ((i = 0; i < 5000; i++)); do
  export node_name="kwok-node-$i"
  envsubst '${node_name}' < config/node.yaml | kubectl apply -f -

  export resource_slice_name="kwok-resource-slice-$i"
  envsubst '${node_name},${resource_slice_name}' < config/resource-slice.yaml | kubectl apply -f -
done
