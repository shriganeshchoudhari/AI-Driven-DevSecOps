import os
import subprocess

root_dir = r"f:\AI Driven DevSecOps\platform"
name = "aiops-engine"

print(f"=========================================")
print(f"LOADING {name} into Kubernetes nodes...")
print(f"=========================================")

tar_path = os.path.join(root_dir, f"{name}.tar")
print(f"Saving {name}:dev-latest to {tar_path}...")
save_cmd = ["docker", "save", "-o", tar_path, f"{name}:dev-latest"]
subprocess.run(save_cmd)

for node in ["desktop-worker", "desktop-control-plane"]:
    print(f"Loading into {node}...")
    # Copy to container
    subprocess.run(["docker", "cp", tar_path, f"{node}:/{name}.tar"])
    # Import inside containerd
    subprocess.run(["docker", "exec", node, "ctr", "-n", "k8s.io", "images", "import", f"/{name}.tar"])
    # Clean up in container
    subprocess.run(["docker", "exec", node, "rm", "-f", f"/{name}.tar"])

# Clean up local tar
if os.path.exists(tar_path):
    os.remove(tar_path)
print(f"Successfully loaded {name}:dev-latest into nodes!")
