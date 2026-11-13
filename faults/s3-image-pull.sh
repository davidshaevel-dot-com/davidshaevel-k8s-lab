# The new revision points at an image tag that does not exist.
fault_supports() { return 0; }
fault_describe() { echo "Image pull: the web Deployment's image tag was changed to 0.1.1, which was never built or pushed."; }
fault_plant() {
  local image
  image=$(k get deployment web -o jsonpath='{.spec.template.spec.containers[0].image}')
  k set image deployment/web web="${image%:*}:0.1.1"
}
fault_heal() { :; } # the baseline re-apply restores the image
