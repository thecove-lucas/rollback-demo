# rollback-demo

A demo of a one-click rollback for ECS services, driven by GitHub Deployments. Every deploy
records a GitHub Deployment (per environment and service); the `Rollback ECS Service` workflow
reads those records to find the last good version, shows what it is about to do, waits for
someone to confirm, and then switches the service back.

Nothing here touches AWS. Deploys go to a simulated ECS (`tools/fake-aws`) whose state lives on the
`fake-ecs` branch; the GitHub Deployment records are real and show up on this repo's Deployments
page.

## Try it

| To | Do |
|---|---|
| Deploy a new version to staging | Change `app/version.txt` on `main` and commit. Both services deploy to staging. |
| Deploy to production | Publish a release tagged `web-v1.0.0` or `search-v1.0.0` (any `web-*` / `search-*` tag). |
| Deploy anywhere by hand | Actions → Deploy ECS Service → Run workflow. Tick "Simulate a deploy the circuit breaker rolls back" to see a failed deploy. |
| Roll back | Actions → Rollback ECS Service → Run workflow. Leave Version empty for the last good version, or give a release tag or commit. The run shows what it will roll back and waits: use Review deployments to approve or reject. |
| See the history | The repo's Deployments page (`staging-web`, `production-search`, ...). |

A rollback needs at least two good deploys of the same service in the same environment.
