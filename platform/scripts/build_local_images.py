import os
import subprocess

root_dir = r"f:\AI Driven DevSecOps\platform"

services = {
    "auth-service": os.path.join(root_dir, "microservices", "auth-service"),
    "payment-service": os.path.join(root_dir, "microservices", "payment-service"),
    "notification-service": os.path.join(root_dir, "microservices", "notification-service"),
    "frontend-service": os.path.join(root_dir, "microservices", "frontend-service"),
    "aiops-engine": os.path.join(root_dir, "aiops")
}

for name, path in services.items():
    print(f"=========================================")
    print(f"BUILDING {name} from {path}...")
    print(f"=========================================")
    
    # 1. Build image
    build_cmd = ["docker", "build", "-t", f"{name}:dev-latest", "."]
    res = subprocess.run(build_cmd, cwd=path)
    if res.returncode != 0:
        print(f"Failed to build {name}")
        continue
    
    print(f"Successfully built {name}:dev-latest")
    
    # 2. Save locally to tar
    tar_path = os.path.join(root_dir, f"{name}.tar")
    print(f"Saving {name}:dev-latest to {tar_path}...")
    save_cmd = ["docker", "save", "-o", tar_path, f"{name}:dev-latest"]
    subprocess.run(save_cmd)
    
    # 3. Load into containers containerd via docker cp + ctr import
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
