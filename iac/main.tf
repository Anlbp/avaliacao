terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.6"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

locals {
  vms = {
    web = { ip = "192.168.100.11", mac = "52:54:00:00:01:11" }
    db  = { ip = "192.168.100.12", mac = "52:54:00:00:01:12" }
  }
}

resource "libvirt_pool" "lab" {
  name = "lab"
  type = "dir"
  path = "/var/lib/libvirt/images/lab"
}

resource "libvirt_network" "lab" {
  name      = "lab"
  mode      = "nat"
  addresses = ["192.168.100.0/24"]

  dhcp {
    enabled = true
  }
}

resource "libvirt_volume" "base" {
  name   = "debian-12-base.qcow2"
  pool   = libvirt_pool.lab.name
  source = "/var/lib/libvirt/images/debian-12-base.qcow2"
  format = "qcow2"
}

resource "libvirt_volume" "disk" {
  for_each       = local.vms
  name           = "${each.key}.qcow2"
  pool           = libvirt_pool.lab.name
  base_volume_id = libvirt_volume.base.id
  size           = 10737418240
}

resource "libvirt_cloudinit_disk" "init" {
  for_each  = local.vms
  name      = "${each.key}-init.iso"
  pool      = libvirt_pool.lab.name
  user_data = templatefile("${path.module}/cloud_init.yaml", {
    hostname = each.key
    ssh_key  = trimspace(file(pathexpand(var.ssh_public_key_path)))
  })
  network_config = yamlencode({
    version = 1
    config = [{
      type        = "physical"
      name        = "eth0"
      mac_address = each.value.mac
      subnets = [{
        type            = "static"
        address         = "${each.value.ip}/24"
        gateway         = "192.168.100.1"
        dns_nameservers = ["1.1.1.1", "8.8.8.8"]
      }]
    }]
  })
}

resource "libvirt_domain" "vm" {
  for_each  = local.vms
  name      = each.key
  memory    = 2048
  vcpu      = 2
  cloudinit = libvirt_cloudinit_disk.init[each.key].id

  cpu {
    mode = "host-passthrough"
  }

  network_interface {
    network_id     = libvirt_network.lab.id
    mac            = each.value.mac
    wait_for_lease = false
  }

  disk {
    volume_id = libvirt_volume.disk[each.key].id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}