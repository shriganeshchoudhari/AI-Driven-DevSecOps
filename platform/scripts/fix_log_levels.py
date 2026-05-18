import os

services = [
    r"f:\AI Driven DevSecOps\platform\microservices\auth-service\src\app.py",
    r"f:\AI Driven DevSecOps\platform\microservices\payment-service\src\app.py",
    r"f:\AI Driven DevSecOps\platform\microservices\notification-service\src\app.py",
    r"f:\AI Driven DevSecOps\platform\microservices\frontend-service\src\app.py",
    r"f:\AI Driven DevSecOps\platform\aiops\src\main.py"
]

for s_path in services:
    if os.path.exists(s_path):
        print(f"Fixing logging logic in {s_path}...")
        with open(s_path, "r", encoding="utf-8") as f:
            content = f.read()
        
        # Replace: getattr(logging, settings.LOG_LEVEL)
        # with:    getattr(logging, settings.LOG_LEVEL.upper())
        updated = content.replace("getattr(logging, settings.LOG_LEVEL)", "getattr(logging, settings.LOG_LEVEL.upper())")
        
        with open(s_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(updated)
