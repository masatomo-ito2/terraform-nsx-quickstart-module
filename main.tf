locals {
  prefix = var.prefix != "" ? var.prefix : random_pet.this.id
}

resource random_pet "this" {
  length = 2
}

module nsx_data {
  source  = "app.terraform.io/masa_org/remote-state/nsx"
  version = "0.0.1"
  environment = lower(var.environment)
}

resource nsxt_policy_segment "public" {
  count               = length(var.public_subnets)
  display_name        = "${local.prefix}-${var.public_subnet_suffix}-${count.index}"
  description         = var.description
  connectivity_path   = nsxt_policy_tier1_gateway.this.path
  transport_zone_path = module.nsx_data.transport_zone_path
  subnet {
    cidr = format("%s%s%s",
      cidrhost(element(var.public_subnets, count.index), 1),
      "/",
      split("/", element(var.public_subnets, count.index))[1]
    )
  }
  advanced_config {
    connectivity = "ON"
  }
}

resource nsxt_policy_segment "private" {
  count               = length(var.private_subnets)
  display_name        = "${local.prefix}-${var.private_subnet_suffix}-${count.index}"
  description         = var.description
  connectivity_path   = nsxt_policy_tier1_gateway.this.path
  transport_zone_path = module.nsx_data.transport_zone_path
  subnet {
    cidr = format("%s%s%s",
      cidrhost(element(var.private_subnets, count.index), 1),
      "/",
      split("/", element(var.private_subnets, count.index))[1]
    )
  }
  advanced_config {
    connectivity = "ON"
  }
}

resource nsxt_policy_tier1_gateway "this" {
  description               = var.description
  display_name              = "${local.prefix}-gateway"
  edge_cluster_path         = module.nsx_data.edge_cluster_path
  failover_mode             = "PREEMPTIVE"
  default_rule_logging      = "false"
  enable_firewall           = "false"
  enable_standby_relocation = "false"
  force_whitelisting        = "true"
  tier0_path                = module.nsx_data.tier0_path
  pool_allocation           = "ROUTING"

  route_advertisement_rule {
    name                      = "rule1"
    action                    = "PERMIT"
    subnets                   = var.public_subnets
    prefix_operator           = "EQ"
    route_advertisement_types = ["TIER1_CONNECTED"]
  }
}

resource nsxt_policy_nat_rule "private" {
  count               = length(var.private_subnets)
  display_name        = "${local.prefix}-${var.private_subnet_suffix}-snat-${count.index}"
  action              = "SNAT"
  translated_networks = [var.private_subnets[count.index]]
  enabled             = var.private_subnets_snat_enabled
  gateway_path        = nsxt_policy_tier1_gateway.this.path
}

resource nsxt_policy_group "private" {
  display_name = "${local.prefix}-${var.private_subnet_suffix}-group"
  description  = var.description

  criteria {
    path_expression {
      member_paths = nsxt_policy_segment.private.*.path
    }
  }
}

resource nsxt_policy_gateway_policy "private" {
  display_name    = "${local.prefix}-${var.private_subnet_suffix}-policy"
  description     = var.description
  category        = "LocalGatewayRules"
  locked          = false
  sequence_number = 3
  stateful        = true
  tcp_strict      = false

  rule {
    display_name       = "default deny inbound"
    destination_groups = [nsxt_policy_group.private.path]
    disabled           = true
    direction          = "IN"
    action             = "DROP"
    logged             = true
    scope              = [nsxt_policy_tier1_gateway.this.path]
  }
}

resource nsxt_policy_lb_service "this" {
  display_name      = "${local.prefix}-lb"
  description       = var.description
  connectivity_path = nsxt_policy_tier1_gateway.this.path
  size              = "SMALL"
  enabled           = true
  error_log_level   = "ERROR"
}
