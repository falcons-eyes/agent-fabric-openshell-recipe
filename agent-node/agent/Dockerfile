# Analyst agent image for the OpenShell sandbox.
#
# The agent itself is standard-library Python: the sandbox policy grants no
# package-index egress, so nothing is installed at run time. iproute2 and nftables
# let the OpenShell supervisor build the network namespace and detect attempts to
# bypass its proxy. OpenShell replaces CMD with its supervisor; pass the command
# after `--` on `openshell sandbox create`.
FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends iproute2 nftables \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1500 app && useradd --uid 1500 --gid app --create-home app \
    && install -d -o app -g app /sandbox
COPY agent.py /app/agent.py
WORKDIR /sandbox
USER app
CMD ["python3", "/app/agent.py", "--probe"]
