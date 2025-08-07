#!/bin/bash

# Clean all nodes with label type=kwok

echo "Cleaning nodes with label type=kwok..."

# Delete nodes with label type=kwok
kubectl delete nodes -l type=kwok

echo "Cleanup completed."