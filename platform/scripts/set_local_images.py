import os
import re

dev_dir = r"f:\AI Driven DevSecOps\platform\environments\dev"
for f_name in os.listdir(dev_dir):
    if f_name.endswith(".yaml"):
        f_path = os.path.join(dev_dir, f_name)
        # Extract the service name from filename: values-auth-service.yaml -> auth-service
        # For values-aiops-engine.yaml -> aiops-engine
        service_name = f_name.replace("values-", "").replace(".yaml", "")
        print(f"Modifying image repository for {f_name} to {service_name}")
        
        with open(f_path, "r", encoding="utf-8") as f:
            content = f.read()
        
        # We replace the image: block with local repository
        # E.g.,
        # image:
        #   tag: dev-latest
        # ->
        # image:
        #   repository: auth-service
        #   tag: dev-latest
        
        pattern = r"image:\s*\n\s*tag:\s*dev-latest"
        replacement = f"image:\n  repository: {service_name}\n  tag: dev-latest"
        
        if "repository:" not in content:
            updated_content = re.sub(pattern, replacement, content)
            with open(f_path, "w", encoding="utf-8", newline="\n") as f:
                f.write(updated_content)
            print(f"Replaced image block in {f_name}")
        else:
            print(f"Repository already overridden in {f_name}")
