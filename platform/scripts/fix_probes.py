import os

charts = [
    r"f:\AI Driven DevSecOps\platform\helm-charts\auth-service\values.yaml",
    r"f:\AI Driven DevSecOps\platform\helm-charts\payment-service\values.yaml",
    r"f:\AI Driven DevSecOps\platform\helm-charts\notification-service\values.yaml",
    r"f:\AI Driven DevSecOps\platform\helm-charts\frontend-service\values.yaml",
    r"f:\AI Driven DevSecOps\platform\helm-charts\aiops-engine\values.yaml"
]

for c_path in charts:
    if os.path.exists(c_path):
        print(f"Fixing startup probe path in {c_path}...")
        with open(c_path, "r", encoding="utf-8") as f:
            content = f.read()
        
        updated = content.replace("path: /startup", "path: /health")
        
        with open(c_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(updated)
