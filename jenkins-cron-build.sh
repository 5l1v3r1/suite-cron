#!/bin/bash
set -e

docker pull ubuntu:14.04
file="Dockerrun.aws.json"
tag="master-${BUILD_NUMBER}"
repo="staffjoy/cron"
s3Bucket="staffjoy-deploy"
s3Path="cron/$tag/"
s3Key="$s3Path$file"

# Add version
sed -i "s/TAG/$tag/" $file

docker build -t $repo:$tag .
docker push $repo:$tag

# Add the Dockerrun to S3 so that beanstalk can access it
aws s3 cp $file s3://$s3Bucket/$s3Path

# Create version
aws elasticbeanstalk create-application-version \
    --application-name stafffjoy-cron \
    --version-label "$tag" \
    --source-bundle "{\"S3Bucket\":\"$s3Bucket\",\"S3Key\":\"$s3Key\"}" 



# Deploy to stage
aws elasticbeanstalk update-environment \
    --environment-name "staffjoy-cron-stage" \
    --version-label "$tag"

# Polling to see whether deploy is done
deploystart=$(date +%s)
timeout=3000 # Seconds to wait before error
threshhold=$((deploystart + timeout))

while true; do
    # Check for timeout
    timenow=$(date +%s)
    if [[ "$timenow" > "$threshhold" ]]; then
        echo "Timeout - $timeout seconds elapsed"
        exit 1
    fi

    # See what's deployed
    version=`aws elasticbeanstalk describe-environments --application-name "stafffjoy-cron" --environment-name "staffjoy-cron-stage" --query "Environments[*].VersionLabel" --output text`
    status=`aws elasticbeanstalk describe-environments --application-name "stafffjoy-cron" --environment-name "staffjoy-cron-stage" --query "Environments[*].Status" --output text`

    if [ "$version" != "$tag" ]; then
        echo "Tag not updated (currently $version). Waiting."
        sleep 10
        continue
    fi
    if [ "$status" != "Ready" ]; then
        echo "System not Ready -it's $status. Waiting."
        sleep 10
        continue
    fi
    break
done
