mes premieres impressions sur kubernetes appelle k8s

je comprend par la que Le k8s est un orchestrateur, et permet de ressoudre des probleme que docker seul ne pourait pas ressoudre .
et le k8s est fait de plusieurs briques, notament les morceaux utiliser pour le construire, on a entre autre le cluster et le control panel qui jouent a eux un role central pour la mise d'un k8s


j'ai appris que le cluster est un ensemble de plusisieurs machine au sein duquel oy trouve le control plan et es nodes .
maintenant chaque node est contitues d'autre parametre 


# les commnandes apprise
kubectl apply -f pod.yml
kubectl delete <name>
ect 


# exercice 

Pour commencer on lance d'abord le 
# minikube start 

# kubectl get nodes, pour lister les nodes 

# kubectl api-ressources , pour voir les ressources  (pod, deployement, Namespace, replicaset ect)


# kubectl get pods -n kube-system , this is to get the kub-sytem 

# kubectl get pod web -o yaml
 

