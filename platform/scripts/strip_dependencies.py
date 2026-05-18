import os
import re

charts_dir = r"f:\AI Driven DevSecOps\platform\helm-charts"
for service in os.listdir(charts_dir):
    chart_yaml_path = os.path.join(charts_dir, service, "Chart.yaml")
    if os.path.exists(chart_yaml_path):
        print(f"Processing: {chart_yaml_path}")
        with open(chart_yaml_path, "r", encoding="utf-8") as f:
            content = f.read()
        
        # Remove dependencies block
        cleaned_content = re.sub(r"dependencies:.*", "", content, flags=re.DOTALL)
        
        with open(chart_yaml_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(cleaned_content.strip() + "\n")
        print(f"Successfully stripped dependencies from {service}")
