#!/bin/bash

while getopts :r:n:p: opt
  do
    case $opt in
      r) region="$OPTARG";;
      n) aminame="$OPTARG";;
      p) profile="$OPTARG";;
      *) echo "Error with Options Input. Cause of failure is most likely that an unsupported parameter was passed or a parameter was passed without a corresponding option." 1>&2 ; exit 64 ;;
    esac
  done

# region validator
case $region in
  us-east-1|us-west-2|us-west-1|eu-west-1|ap-southeast-1|ap-northeast-1|sa-east-1|ap-southeast-2|eu-central-1) ;;
  *) echo "The \"$region\" region does not exist. You must specify a valid region (example: -r us-east-1 or -r us-west-2)." 1>&2 ; exit 64;;
esac

aws --profile $profile --region $region ec2 describe-images --filters Name=name,Values=$aminame  | jq -r '.Images[].ImageId'
