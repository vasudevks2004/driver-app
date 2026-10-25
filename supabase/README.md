# Backend ownership

The existing function/setup files in this directory predate the reliability release and are retained for history. For this release, deploy the reviewed backend from `Buildathon-HireD-Brototype-2026/UniT7` PR #12. Its migrations, shared Worker, trusted application review and updated onboarding handler form one contract.

Do not deploy these legacy copies in place of that shared backend. They do not implement the new draft, review, encryption or cleanup lifecycle. Full backend contract tests remain in the private shared repository.
