import os

dev_dir = r"f:\AI Driven DevSecOps\platform\environments\dev"
for f_name in os.listdir(dev_dir):
    if f_name.endswith(".yaml"):
        f_path = os.path.join(dev_dir, f_name)
        print(f"Modifying affinity for: {f_path}")
        with open(f_path, "r", encoding="utf-8") as f:
            content = f.read()
        
        if "nodeSelector:" not in content:
            updated_content = content.rstrip() + "\n\nnodeSelector: {}\naffinity: {}\ntolerations: []\n"
            with open(f_path, "w", encoding="utf-8", newline="\n") as f:
                f.write(updated_content)
            print(f"Appended nodeSelector override to {f_name}")
        else:
            print(f"nodeSelector already overridden in {f_name}")
