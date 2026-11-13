# The new revision asks for more memory than the namespace quota has left.
fault_supports() { return 0; }
fault_describe() { echo "Quota rejection: the web container's memory request was raised to 900Mi; the ResourceQuota lab-quota (requests.memory 1Gi) rejects the new pods."; }
fault_plant() { k set resources deployment/web -c web --requests=memory=900Mi --limits=memory=1Gi; }
fault_heal() { :; } # the baseline re-apply restores the resources
