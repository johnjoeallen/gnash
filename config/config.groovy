# Global provisioning configuration template.
# Copy or rename this file for host-specific overrides.

steps {
  adminGroupNopass {
    adminGroup = "admin"
    addCurrentUser = false
    users = ["jallen", "maria"]
  }

  essentials {
    packages = [
      "curl",
      "wget",
      "zip",
      "unzip",
      "rsync",
      "ca-certificates",
      "gnupg",
      "apt-transport-https",
      "vim-gtk3"
    ]
  }

  ntp {
    enabled = true
  }

  nisSetup {
    domain = "dublinux.net"
    server = "10.0.0.1"
  }

  nsswitch {
    enabled = true
  }

  pamMkhomedir {
    enabled = true
  }

  dockerInstall {
    enabled = true
  }

  dockerDataRoot {
    target = "/data/docker"
  }

  dockerGroup {
    ensureUser = true
    users = ["jallen", "maria"]
    enabled = true
  }

  sdkmanInstall {
    enabled = true
  }

  sdkmanMaven {
    version = null
    enabled = true
  }

  sdkmanJava {
    defaultJava = "21.0.8-tem"
    javaVersions = [
      "17.0.16-tem",
      "21.0.8-tem",
      "25-tem"
    ]
    enabled = true
  }

  insomnia {
    enabled = true
  }

  jetbrainsToolbox {
    enabled = true
  }

  googleChrome {
    enabled = true
  }

  extendSuspend {
    enabled = true
    idleAction = "suspend"
    timeout = "PT2H"
  }
}
