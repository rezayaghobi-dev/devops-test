# GitLab stack (self-hosted)

GitLab CE and its container registry behind Traefik (TLS), plus a Docker-executor runner on the same network (`web_net`).
The pipeline for this repo is in `.gitlab-ci.yml` in this folder (included from the repo root).

Register a runner (create it in Admin > CI/CD > Runners first, then use its token):

    docker exec gitlab-runner gitlab-runner register --non-interactive \
      --url http://gitlab:80 --token <RUNNER_TOKEN> \
      --executor docker --docker-image docker:cli \
      --docker-network-mode web_net \
      --docker-volumes /var/run/docker.sock:/var/run/docker.sock \
      --clone-url http://gitlab:80

Where registry.gitlab.com is unreachable, add this to the runner's [runners.docker] section in config.toml:
`helper_image = "gitlab/gitlab-runner-helper:x86_64-latest"`
