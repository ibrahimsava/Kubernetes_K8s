# Exercises - Module 01

Do these without looking at the course first. Write your observations in `../notes/`.

---

## Exercise 1: Explore your cluster

1. Start Minikube and list the nodes.
2. List all Pods in **all namespaces**. Which ones are in `kube-system`?
3. Run `kubectl api-resources`. How many resource types can you spot? Find `pods`, `services` and `deployments`.

**Questions**
- Which Pod in `kube-system` is the API server? Which one is etcd?
- What is the status of your node, and what does it mean?

---

## Exercise 2: Imperative Pod

1. Create a Pod named `web` with the image `nginx:1.27` using `kubectl run`.
2. Show on which node and with which IP it runs (`-o wide`).
3. Display its full YAML with `kubectl get pod web -o yaml`.

**Questions**
- What fields appear in the YAML that you never wrote? Who added them?
- Which section of the YAML is `spec` and which one is `status`?

---

## Exercise 3: Declarative Pod

1. Write your own manifest `my-pod.yaml` for a Pod named `my-nginx` with:
   - the label `app: my-nginx`
   - the image `nginx:1.27`
   - container port `80`
2. Apply it, then check that it is running.
3. Change the label to `app: web` in the file and run `kubectl apply` again. Check with `kubectl get pods --show-labels`.

**Bonus:** use `kubectl explain pod.spec.containers.ports` to find what other fields a port accepts.

---

## Exercise 4: Access and inspect

1. Use `port-forward` to reach your Pod at http://localhost:8080.
2. Read its logs. Refresh the page in the browser and check that new log lines appear (`kubectl logs -f`).
3. Open a shell inside the container and display the contents of `/usr/share/nginx/html/index.html`.

---

## Exercise 5: Break it on purpose 🔧

Create a Pod with a **wrong image tag**:

```bash
kubectl run broken --image=nginx:does-not-exist
```

1. Watch the status with `kubectl get pods -w`.
2. Find the cause using `kubectl describe pod broken` (read the Events).
3. Fix it: delete the Pod and recreate it with a valid tag.

Now create a Pod that **crashes**:

```bash
kubectl run crasher --image=busybox:1.36 -- sh -c "echo starting; exit 1"
```

1. What status do you get after a few seconds?
2. Read the logs. What do they say?
3. Why does Kubernetes keep restarting it? Look at `kubectl describe` for the restart count.

**Write down** in your notes what each status (`ErrImagePull`, `ImagePullBackOff`, `CrashLoopBackOff`) looked like and how you diagnosed it.

---

## Exercise 6: Pods are ephemeral

1. Delete the Pod `my-nginx`.
2. Wait 30 seconds and run `kubectl get pods`.
3. Is it back? Why or why not?

This is the problem that Deployments solve in module 02.

---

## Final self-check questions

1. What is the difference between the control plane and a node?
2. What does the scheduler do? And the kubelet?
3. Why do we prefer `kubectl apply -f` over `kubectl run` in real projects?
4. What are the first three commands you run when a Pod is not working?
5. Why can't you rely on a Pod's IP address?

---

## Cleanup

```bash
kubectl delete pod --all
```