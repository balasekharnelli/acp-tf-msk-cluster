/**
* Module usage:
*
*      module "msk_cluster" {
*        source = "git::https://github.com/UKHomeOffice/acp-tf-msk-cluster?ref=master"
*
*        name                   = "msktestclutser"
*        msk_instance_type      = "kafka.m5.large"
*        kafka_version          = "1.1.1"
*        environment            = "${var.environment}"
*        number_of_broker_nodes = "3"
*        subnet_ids             = ["${data.aws_subnet_ids.suben_id_name.ids}"]
*       vpc_id                 = "${var.vpc_id}"
*        ebs_volume_size        = "50"
*        cidr_blocks            = ["${values(var.compute_cidrs)}"]
*      }
*
*      module "msk_cluster_with_config" {
*        source = "git::https://github.com/UKHomeOffice/acp-tf-msk-cluster?ref=master"
*
*        name                   = "msktestclusterwithconfig"
*        msk_instance_type      = "kafka.m5.large"
*        kafka_version          = "1.1.1"
*        environment            = "${var.environment}"
*        number_of_broker_nodes = "3"
*        subnet_ids             = ["${data.aws_subnet_ids.suben_id_name.ids}"]
*        vpc_id                 = "${var.vpc_id}"
*        ebs_volume_size        = "50"
*        cidr_blocks            = ["${values(var.compute_cidrs)}"]
*
*        config_name           = "testmskconfig"
*        config_kafka_versions = ["1.1.1"]
*        config_description    = "Test MSK configuration"
*
*        config_server_properties = <<PROPERTIES
*      auto.create.topics.enable = true
*      delete.topic.enable = true
*      PROPERTIES
*      }
*
*
 */

data "aws_caller_identity" "current" {}

resource "aws_security_group" "sg_msk" {
  name        = "${var.name}-kafka-security-group"
  description = "Allow kafka traffic"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    cidr_blocks = ["${var.cidr_blocks}"]
  }

  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["${var.cidr_blocks}"]
  }

  ingress {
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = ["${var.cidr_blocks}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${merge(var.tags, map("Name", format("%s-%s", var.environment, var.name)), map("Env", var.environment))}"
}

resource "aws_kms_key" "kms" {
  description = "msk cluster kms key"
  policy      = "${data.aws_iam_policy_document.kms_key_policy_document.json}"
  tags        = "${merge(var.tags, map("Name", format("%s-%s", var.environment, var.name)), map("Env", var.environment))}"
}

resource "aws_kms_alias" "msk_cluster_kms_alias" {
  name          = "alias/${var.name}"
  target_key_id = "${aws_kms_key.kms.key_id}"
}

resource "aws_msk_cluster" "msk_kafka" {
  count = "${var.config_name == "" && var.config_arn == "" ? 1 : 0}"

  cluster_name           = "${var.name}"
  kafka_version          = "${var.kafka_version}"
  number_of_broker_nodes = "${var.number_of_broker_nodes}"

  broker_node_group_info {
    instance_type   = "${var.msk_instance_type}"
    ebs_volume_size = "${var.ebs_volume_size}"
    client_subnets  = ["${var.subnet_ids}"]
    security_groups = ["${aws_security_group.sg_msk.id}"]
  }

  client_authentication {
    tls {
      certificateauthorityArnList = ["${var.CertificateauthorityarnList}"]
    }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = "${aws_kms_key.kms.arn}"

    encryption_in_transit {
      client_broker = "${var.client_broker}"
    }
  }

  tags = "${merge(var.tags, map("Name", format("%s-%s", var.environment, var.name)), map("Env", var.environment))}"
}

resource "aws_msk_cluster" "msk_kafka_with_config" {
  count = "${var.config_name != "" || var.config_arn != "" ? 1 : 0}"

  cluster_name           = "${var.name}"
  kafka_version          = "${var.kafka_version}"
  number_of_broker_nodes = "${var.number_of_broker_nodes}"

  broker_node_group_info {
    instance_type   = "${var.msk_instance_type}"
    ebs_volume_size = "${var.ebs_volume_size}"
    client_subnets  = ["${var.subnet_ids}"]
    security_groups = ["${aws_security_group.sg_msk.id}"]
  }

  client_authentication {
    tls {
      certificateauthorityArnList = ["${var.CertificateauthorityarnList}"]
    }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = "${aws_kms_key.kms.arn}"

    encryption_in_transit {
      client_broker = "${var.client_broker}"
    }
  }

  configuration_info {
    arn      = "${coalesce(var.config_arn, join("", aws_msk_configuration.msk_kafka_config.*.arn))}"
    revision = "${coalesce(var.config_revision, join("", aws_msk_configuration.msk_kafka_config.*.latest_revision))}"
  }

  tags = "${merge(var.tags, map("Name", format("%s-%s", var.environment, var.name)), map("Env", var.environment))}"
}

resource "aws_msk_configuration" "msk_kafka_config" {
  count = "${var.config_name != "" && var.config_arn == "" ? 1 : 0}"

  kafka_versions = "${var.config_kafka_versions}"
  name           = "${var.config_name}"
  description    = "${var.config_description}"

  server_properties = "${var.config_server_properties}"
}

# creates CA for msk Cluster without custom config
resource "aws_acmpca_certificate_authority" "msk_kafka_with_ca" {
  count = "${var.certificateauthority == "true" && var.config_arn == "" || var.config_name == "" ? 1 : 0}"

  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name = "example.com"
    }
  }

  type                            = "${var.type}"
  permanent_deletion_time_in_days = 7
  tags                            = "${merge(var.tags, map("Name", format("%s-%s", var.environment, var.name)), map("Env", var.environment))}"
}

# CA for msk Cluster with custom config

resource "aws_acmpca_certificate_authority" "msk_kafka_ca_with_config" {
  count = "${var.certificateauthority == 0 && var.config_name != "" || var.config_arn != "" ? 1 : 0}"

  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      given_name = "${var.name}"
    }
  }

  type                            = "${var.type}"
  permanent_deletion_time_in_days = 7
  tags                            = "${merge(var.tags, map("Name", format("%s-%s", var.environment, var.name)), map("Env", var.environment))}"
}

resource "aws_iam_user" "msk_acmpca_iam_user" {
  count = "${length(var.certificateauthority) == 1 && length(var.acmpca_iam_user_name) != 0 ? 1 : 0}"
  name  = "${var.acmpca_iam_user_name}"
  path  = "/"
}

#policy #policy attachment for custom policy
resource "aws_iam_policy" "acmpca_policy_with_msk_config_policy" {
  count  = "${length(var.acmpca_iam_user_name) != 0 && var.certificateauthority == 1 && var.config_name != "" || var.config_arn != "" ? 1 : 0}"
  name   = "${var.name}-acmpaPolicy"
  policy = "${data.aws_iam_policy_document.acmpca_policy_document_with_msk_config.json}"
}

resource "aws_iam_user_policy_attachment" "acmpca_with_msk_config_policy_attachement" {
  count      = "${length(var.acmpca_iam_user_name) != 0 && var.certificateauthority == 1 && var.config_name != "" || var.config_arn != "" ? 1 : 0}"
  user       = "${element(aws_iam_user.msk_acmpca_iam_user.*.name, count.index)}"
  policy_arn = "${aws_iam_policy.acmpca_policy_with_msk_config_policy.arn}"
}

#policy attachment for default policy
resource "aws_iam_policy" "acmpca_policy_with_msk_policy" {
  count  = "${length(var.acmpca_iam_user_name) != 0 && var.certificateauthority == 0 && var.config_name == "" || var.config_arn == "" ? 1 : 0}"
  name   = "${var.name}-acmpaPolicy"
  policy = "${data.aws_iam_policy_document.acmpca_policy_document_with_msk_only.json}"
}

resource "aws_iam_user_policy_attachment" "acmpca_policy_attachement" {
  count      = "${length(var.acmpca_iam_user_name) != 0 && var.certificateauthority == 0 && var.config_name == "" || var.config_arn == "" ? 1 : 0}"
  user       = "${element(aws_iam_user.msk_acmpca_iam_user.*.name, count.index)}"
  policy_arn = "${aws_iam_policy.acmpca_policy_with_msk_policy.arn}"
}