import subprocess

services = ["auth-service", "payment-service", "notification-service", "frontend-service", "aiops-engine"]

print("=========================================")
print("UPGRADING ALL 5 HELM CHARTS IN DEV NS...")
print("=========================================")

for svc in services:
    print(f"Deploying {svc}...")
    cmd = [
        "helm", "upgrade", "--install", svc,
        f"./helm-charts/{svc}",
        "-f", f"./environments/dev/values-{svc}.yaml",
        "-n", "dev",
        "--create-namespace"
    ]
    res = subprocess.run(cmd, cwd=r"f:\AI Driven DevSecOps\platform")
    if res.returncode == 0:
        print(f"Successfully deployed {svc}!")
    else:
        print(f"Failed to deploy {svc}")
