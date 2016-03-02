#!/bin/bash -
# Originally written:
# Author: Colin Johnson / colin@cloudavail.com
# Date: 2012-02-27
# Version 0.5
# License Type: GNU GENERAL PUBLIC LICENSE, Version 3
#
# Port to current aws tooling and extensive modification:
# Author: Pete Ehlke / pete.ehlke@aboveproperty.com
# Date: 2016-03-02
#
#####
#as-update-launch-config start

warn() {
    echo "$1" >&2
}

die() {
    warn "ERROR: $1"
    exit 1
}

#gets an AMI from set of inputs
getimageidcurl()
{
	#get list of AMIs - format is region,bitdepth,storage,ami-id, -s is required to prevent curl from outputing progress meter to stderr
	amimap=`curl -s ${awsec2amimap}`
	#gets instanceid from downloaded file
	imageid=`echo "$amimap" | grep "$region,$bits,$storage" | cut -d ',' -f4`
	echo "AMI ID $imageid will be used for the new Launch Configuration. Note that as-update-launch-config uses Amazon Linux AMIs by default."
}

#determines that the user provided AMI does, in fact, exit
imageidvalidation()
{
	#amivalid redirects stderr to stdout - if the user provided AMI does not exist, the if statement will exit as-update-launch-config.sh else it is assumed that the user provided AMI exists
	amivalid=$(aws ec2 describe-images --image-ids $imageid --profile rfc822-dev --region $region)
	if [[ $amivalid =~ "InvalidAMIID.NotFound" ]]
		then echo "The AMI ID $imageid could not be found. If you specify an AMI (-m) it must exist and be in the given region (-r). Note that region (-r defaults to \"us-east-1\" if not given." 1>&2 ; exit 64
	else echo "The user provided AMI \"$imageid\" will be used when updating the Launch Configuration for the Auto Scaling Group \"$asgroupname.\""
	fi
}

# How to get the imageid by name
# aws --profile rfc822-dev --region us-east-1 ec2 describe-images --filters Name=name,Values=pde-test-2  | jq -r '.Images[].ImageId'

#confirms that executables required for succesful script execution are available
prerequisitecheck()
{
	for prerequisite in basename cut curl date head grep aws jq
	do
		#use of "hash" chosen as it is a shell builtin and will add programs to hash table, possibly speeding execution. Use of type also considered - open to suggestions.
		hash $prerequisite &> /dev/null
		if [[ $? == 1 ]] #has exits with exit status of 70, executable was not found
			then echo "In order to use `basename $0`, the executable \"$prerequisite\" must be installed." 1>&2 ; exit 70
		fi
	done
}

#calls prerequisitecheck function to ensure that all executables required for script execution are available
prerequisitecheck

#sets as-update-launch-config Defaults
awsec2amimap="http://s3.amazonaws.com/colinjohnson-cloudavailprd/aws-ec2-ami-map.txt"
region="us-east-1"
# dateymd=`date +"%F"`
dateymd=$(date -u +"%Y-%m-%d-%H-%M-%S-%Z")

#handles options processing
while getopts :a:i:u:b:s:t:p:r:m: opt
	do
		case $opt in
			a) asgroupname="$OPTARG";;
			i) instancetype="$OPTARG";;
			u) userdata="$OPTARG";;
			b) bits="$OPTARG";;
			s) storage="$OPTARG";;
			t) testmode="$OPTARG";;
      p) profile="$OPTARG";;
			r) region="$OPTARG";;
			m) imageid="$OPTARG";;
			*) echo "Error with Options Input. Cause of failure is most likely that an unsupported parameter was passed or a parameter was passed without a corresponding option." 1>&2 ; exit 64 ;;
		esac
	done

# Set the aws command line template
AWS="aws --profile $profile --region $region"

#sets previewmode - will echo commands rather than performing work
case $testmode in
	true|True) previewmode="echo"; echo "Preview Mode is set to $testmode" 1>&2 ;;
	""|false|False) previewmode="";;
	*) echo "You specified \"$testmode\" for Preview Mode. If specifying a Preview Mode you must specific either \"true\" or \"false.\"" 1>&2 ; exit 64 ;;
esac

# instance-type validator
case $instancetype in
	t1.micro|m1.small|c1.medium|m1.medium) bits=$bits ;
	# bit depth validator for micro to medium instances - demands that input of bits for micro to medium size instances be 32 or 64 bit
		if [[ $bits -ne 32 && bits -ne 64 ]]
			then echo "You must specify either a 32-bit (-b 32) or 64-bit (-b 64) platform for the \"$instancetype\" EC2 Instance Type." 1>&2 ; exit 64
		fi ;;
	t1.micro|m1.small|m1.medium|m1.large|m1.xlarge|m3.medium|m3.large|m3.xlarge|m3.2xlarge|m4.large|m4.xlarge|m4.2xlarge|m4.4xlarge|m4.10xlarge|t2.nano|t2.micro|t2.small|t2.medium|t2.large|m2.xlarge|m2.2xlarge|m2.4xlarge|cr1.8xlarge|i2.xlarge|i2.2xlarge|i2.4xlarge|i2.8xlarge|hi1.4xlarge|hs1.8xlarge|c1.medium|c1.xlarge|c3.large|c3.xlarge|c3.2xlarge|c3.4xlarge|c3.8xlarge|c4.large|c4.xlarge|c4.2xlarge|c4.4xlarge|c4.8xlarge|cc1.4xlarge|cc2.8xlarge|g2.2xlarge|g2.8xlarge|cg1.4xlarge|r3.large|r3.xlarge|r3.2xlarge|r3.4xlarge|r3.8xlarge|d2.xlarge|d2.2xlarge|d2.4xlarge|d2.8xlarge) bits=64;;
	"") echo "You did not specify an EC2 Instance Type. You must specify a valid EC2 Instance Type (example: -i m1.small or -i m1.large)." 1>&2 ; exit 64;;
	*) echo "The \"$instancetype\" EC2 Instance Type does not exist. You must specify a valid EC2 Instance Type (example: -i m1.small or -i m1.large)." 1>&2 ; exit 64;;
esac

# user-data validator
if [[ ! -f $userdata ]]
	then echo "The user-data file \"$userdata\" does not exist. You must specify a valid user-data file (example: -u /path/to/user-data.txt)." 1>&2 ; exit 64
fi

# storage validator
case $storage in
	ebs|EBS) storage=EBS;;
	s3|S3) storage=S3;;
	"") storage=EBS ;; # if no storage type is set - default to EBS
	*) echo "The \"$storage\" storage type does not exist. You must specify a valid storage type (either: -s ebs or -s s3)." 1>&2 ; exit 64;;
esac

# region validator
case $region in
	us-east-1|us-west-2|us-west-1|eu-west-1|ap-southeast-1|ap-northeast-1|sa-east-1|ap-southeast-2|eu-central-1) ;;
	*) echo "The \"$region\" region does not exist. You must specify a valid region (example: -r us-east-1 or -r us-west-2)." 1>&2 ; exit 64;;
esac

# as-group-name validator - need to also include "command not found" if as-describe-auto-scaling-groups doesn't fire
if [[ -z $asgroupname ]]
	then echo "You must specify an Auto Scaling Group name (example: -a asgname)." 1>&2 ; exit 64
fi

#creates list of Auto Scaling Groups
asgresult=`$AWS autoscaling describe-auto-scaling-groups --auto-scaling-group-names $asgroupname `

#user response for Auto Scaling Group lookup - alerts user if Auto Scaling Group was not found.
if [[ $(echo $asgresult | jq -r '.AutoScalingGroups[].AutoScalingGroupName') != "$asgroupname" ]]
    then echo "The Auto Scaling Group named \"$asgroupname\" does not exist. You must specify an Auto Scaling Group that exists." 1>&2 ; exit 64
fi

#if $imageid has a length of non-zero call imageidvalidation else call getimageid.
if [[ -n $imageid ]]
	then imageidvalidation
else
	getimageidcurl
fi

#gets current launch-config
launch_config_current=$(echo $asgresult | jq -r '.AutoScalingGroups[].LaunchConfigurationName')

aslcresult=$($AWS autoscaling describe-launch-configurations --launch-configuration-names $launch_config_current)

# FIXME allow for more than one security group
launch_config_security_group=$(echo $aslcresult | jq -r '.LaunchConfigurations[].SecurityGroups[]')
launch_config_key=$(echo $aslcresult | jq -r '.LaunchConfigurations[].KeyName')

echo "The Auto Scaling Group \"$asgroupname\" uses the security group \"$launch_config_security_group\" in region $region." 1>&2
echo "The Auto Scaling Group \"$asgroupname\" uses the key \"$launch_config_key\" in region $region" 1>&2

#code below searches for unique identifier for launch-config - without a unique identifier, launch config creation would fail.
unique_lc_name_found=0
lc_uniq_id=1

aslc_list=$($AWS autoscaling describe-launch-configurations | jq -r '.LaunchConfigurations[].LaunchConfigurationName')

while [[ $unique_lc_name_found < 1 ]]
do
	#tests if launch-config name will be unique
	if [[ $aslc_list =~ "$asgroupname-$dateymd-id-$lc_uniq_id" ]]
		then lc_uniq_id=$((lc_uniq_id+1))
	else
		unique_lc_name_found=1 ; #for testing "Launch Condifuration Named: \"$asgroupname-$dateymd-id-$lc_uniq_id.\""
	fi
done

launchconfig_new="$asgroupname-$dateymd-id-$lc_uniq_id-$imageid"

echo "A new Launch Configuration named \"$launchconfig_new\" for Auto Scaling Group \"$asgroupname\" will be created in region $region using EC2 Instance Type \"$instancetype\" and AMI \"$imageid.\""
#Create Launch Config
$previewmode $AWS autoscaling create-launch-configuration --launch-configuration-name $launchconfig_new --image-id $imageid --instance-type $instancetype --security-groups $launch_config_security_group --key-name $launch_config_key --user-data file://$userdata || die "Failed to create new launch config $launchconfig_new"

#Update Auto Scaling Group
$previewmode $AWS autoscaling update-auto-scaling-group --auto-scaling-group-name $asgroupname --launch-configuration $launchconfig_new || die "Failed to update ASG $asgroupname"

echo "Done"
