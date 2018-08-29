# Codis-k8s
Codis-k8s scripts, based on https://github.com/CodisLabs/codis/tree/release3.2/kubernetes

Please check start.sh for details.

# Examples:
>     # to clean-up all the deployments, 
>     # except pv and pvc
>     ./start.sh cleanup test

>     # to build-up all the deployments.
>     ./start.sh buildup test

>     # scale proxy
>     ./start.sh scale-proxy test 8
>     ./start.sh scale-proxy test 2

>     # scale server
>     ./start.sh scale-server test 8

# Note:
>     reduce the number of codis-server-$product_name, does not support.

