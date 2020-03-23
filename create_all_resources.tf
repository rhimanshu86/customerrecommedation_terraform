# creating EMR cluster with default roles
resource "aws_emr_cluster" "cluster" {
  name          = "emr-matching-no-recommedation"
  release_label = "emr-5.7.1"
  applications  = ["Spark"]


  termination_protection            = false
  keep_job_flow_alive_when_no_steps = false

  ec2_attributes {

     instance_profile = "EMR_EC2_DefaultRole"

   }

  master_instance_group {
    instance_type = "m4.large"
  }

  core_instance_group {
    instance_type  = "m4.large"
    instance_count = 1

    ebs_config {
      size                 = "20"
      type                 = "gp2"
      volumes_per_instance = 1
    }
  }

  ebs_root_volume_size = 20

  tags = {
    role = "assesment"
    env  = "test"
  }

  bootstrap_action {
    path = "s3://himanshu-assesment-bucket/run_app.sh"
    name = "bootstraping"
    args = ["instance.isMaster=true", "copy files from s3:// buckets to /tmp"]
  }
  log_uri = "s3://emr-logs-sample/"


  step {
      action_on_failure = "TERMINATE_CLUSTER"
      name   = "Launch Spark Job"

      hadoop_jar_step {
        jar  = "command-runner.jar"
        args = ["spark-submit","/tmp/assesment_solution/upload_data.py"]
      }
  }



  service_role = "EMR_DefaultRole"
}


# create dynamo DB called assesment_customer_match

resource "aws_dynamodb_table" "assesment_customer_match" {
  name           = "assesment_customer_match"
  billing_mode   = "PAY_PER_REQUEST"
  read_capacity  = 2
  write_capacity = 2
  hash_key       = "customer"

  attribute {
    name = "customer"
    type = "S"
  }
  tags = {
    Name        = "assement_dynamodb-table-1"
    Environment = "test"
  }
}


# create rest api gateway
resource "aws_api_gateway_rest_api" "get_cust_details" {
  name        = "get customer details"
  description = "get top 10 matching customer"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.get_cust_details.id
  parent_id   = aws_api_gateway_rest_api.get_cust_details.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.get_cust_details.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

# Integrate api gateway with lambda
resource "aws_api_gateway_integration" "lambda" {
   rest_api_id = aws_api_gateway_rest_api.get_cust_details.id
   resource_id = aws_api_gateway_method.proxy.resource_id
   http_method = aws_api_gateway_method.proxy.http_method

   integration_http_method = "POST"
   type                    = "AWS_PROXY"
   uri                     = aws_lambda_function.get_cust_match.invoke_arn
 }

 resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = aws_api_gateway_rest_api.get_cust_details.id
  resource_id   = aws_api_gateway_rest_api.get_cust_details.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = aws_api_gateway_rest_api.get_cust_details.id
  resource_id = aws_api_gateway_method.proxy_root.resource_id
  http_method = aws_api_gateway_method.proxy_root.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_cust_match.invoke_arn
}

# deploy api gateway to test stage  .
resource "aws_api_gateway_deployment" "get_cust_details_deployed" {
   depends_on = [
     aws_api_gateway_integration.lambda,
     aws_api_gateway_integration.lambda_root,
   ]

   rest_api_id = aws_api_gateway_rest_api.get_cust_details.id
   stage_name  = "test"
 }

#apply permissions to lambda .
 resource "aws_lambda_permission" "apigw" {
   statement_id  = "AllowAPIGatewayInvoke"
   action        = "lambda:InvokeFunction"
   function_name = aws_lambda_function.get_cust_match.function_name
   principal     = "apigateway.amazonaws.com"


   source_arn = "${aws_api_gateway_rest_api.get_cust_details.execution_arn}/*/*"
 }

# get output of api gateway created
 output "base_url" {
  value = aws_api_gateway_deployment.get_cust_details_deployed.invoke_url
}

# provide = aws and region eu-central-1
provider "aws" {
  region          = "eu-central-1"
}

data "archive_file" "lambda_zip" {
    type          = "zip"
    source_file   = "lambda_function.py"
    output_path   = "lambda_function.zip"
}

# Create the function
resource "aws_lambda_function" "get_cust_match" {
  filename         = "lambda_function.zip"
  function_name    = "get_cust_details"
  role             = "${aws_iam_role.assesment_role.arn}"
  handler          = "lambda_function.lambda_handler"
  source_code_hash = "${data.archive_file.lambda_zip.output_base64sha256}"
  runtime          = "python3.8"
}

#

# IAM roles and policy 
resource "aws_iam_role_policy" "assesment_policy" {
  name = "assesment_policy"
  role = aws_iam_role.assesment_role.id

  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": [
          "lambda:*",
          "s3:*",
          "apigateway:*",
          "dynamodb:*",
          "cloudwatch:*"
        ],
        "Effect": "Allow",
        "Resource": "*"
      }
    ]
  }
  EOF
}
resource "aws_iam_role" "assesment_role" {
  name = "assesment_role"

  assume_role_policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "lambda.amazonaws.com",
          "Service": "s3.amazonaws.com",
          "Service": "cloudwatch.amazonaws.com",
          "Service": "dynamodb.amazonaws.com",
          "Service": "apigateway.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  }
  EOF
}
