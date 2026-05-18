import os

dev_dir = r"f:\AI Driven DevSecOps\platform\environments\dev"
for f_name in os.listdir(dev_dir):
    if f_name.endswith(".yaml"):
        f_path = os.path.join(dev_dir, f_name)
        print(f"Modifying: {f_path}")
        with open(f_path, "r", encoding="utf-8") as f:
            content = f.read()
        
        if "monitoring:" not in content:
            updated_content = content.rstrip() + "\n\nmonitoring:\n  enabled: false\n"
            with open(f_path, "w", encoding="utf-8", newline="\n") as f:
                f.write(updated_content)
            print(f"Appended monitoring block to {f_name}")
        else:
            print(f"monitoring already present in {f_name}")
