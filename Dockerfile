# [VULN-11] CWE-250/CWE-1395 Multiple Dockerfile misconfigurations for IaC scanning.
FROM node:14                      # outdated base image, mutable major tag
ENV AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYFAKEDEMOKEY   # secret in ENV
WORKDIR /app
COPY . .
RUN npm install                    # no --ignore-scripts, installs vulnerable deps
EXPOSE 8080
# Runs as root (no USER directive) and uses ADD-from-URL anti-pattern below.
ADD http://example.com/setup.sh /setup.sh
RUN chmod 777 /setup.sh
CMD ["node", "tools/scripts/report.js"]
