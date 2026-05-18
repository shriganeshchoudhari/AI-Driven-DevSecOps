import os
import re

charts_dir = r"f:\AI Driven DevSecOps\platform\helm-charts"

# We want to replace the default nodeSelector, tolerations, and affinity blocks in each service's values.yaml
for service_name in os.listdir(charts_dir):
    service_path = os.path.join(charts_dir, service_name)
    if os.path.isdir(service_path):
        values_path = os.path.join(service_path, "values.yaml")
        if os.path.exists(values_path):
            print(f"Processing: {values_path}")
            with open(values_path, "r", encoding="utf-8") as f:
                content = f.read()

            # Replace nodeSelector block
            # We look for nodeSelector: and everything under it until tolerations: or affinity:
            # Let's replace the whole section starting from nodeSelector to the end of affinity with empty defaults
            pattern = r"(# -- Node selector\nnodeSelector:[\s\S]*?# -- Affinity / anti-affinity\naffinity:[\s\S]*?node-type:[\s\S]*?)\n\n# -- Probes"
            # Since regex matching can be fragile due to line breaks or order, let's do a reliable replacement using key names
            
            # 1. Replace nodeSelector: ... with nodeSelector: {}
            content = re.sub(
                r"nodeSelector:\s*\n\s*node-type:\s*general-purpose",
                "nodeSelector: {}",
                content
            )
            
            # 2. Replace tolerations: ... with tolerations: []
            content = re.sub(
                r"tolerations:\s*\n\s*-\s*key:\s*\"CriticalAddonsOnly\"[\s\S]*?tolerationSeconds:\s*300",
                "tolerations: []",
                content
            )
            # Also replace any other tolerations variation
            content = re.sub(
                r"tolerations:\s*\n\s*-\s*key:\s*CriticalAddonsOnly[\s\S]*?tolerationSeconds:\s*300",
                "tolerations: []",
                content
            )

            # 3. Replace affinity: ... with affinity: {}
            content = re.sub(
                r"affinity:\s*\n\s*podAntiAffinity:[\s\S]*?-\s*compute-optimized",
                "affinity: {}",
                content
            )
            
            with open(values_path, "w", encoding="utf-8", newline="\n") as f:
                f.write(content)
            print(f"Cleaned {service_name}/values.yaml successfully.")
