---
title: "[Vultr] Fix Shebang in Startup Script"
date: 2023-07-11
slug: "MicahZoltu-vultr-raid0-2"
categories:
    - "Open Source"
tags:
    - "Vultr"
    - "Bash"
externalUrl: "https://github.com/MicahZoltu/vultr-raid0/pull/2"
---

### Contribution Description

Fixed a syntax error in the `startup.sh` script by updating the shebang to `#!/bin/bash`.
This ensures the script executes correctly across different environments where `sh` might not be `bash` compatible.

[View on GitHub](https://github.com/MicahZoltu/vultr-raid0/pull/2)
