
KWOK_NODES=1
for ((i = 0; i < 10; i++)); do
  export node_name="kwok-node-$i"
  export resource_slice_name="kwok-resource-slice-$i"
  envsubst '${node_name}' < kwok-node.yaml | kubectl apply -f -
  envsubst '${node_name},${resource_slice_name}' < resource-slice.yaml | kubectl apply -f -
done
