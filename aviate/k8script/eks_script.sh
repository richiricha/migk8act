#!/bin/bash
CLUSTER=$1
REGION=$2
ZONES=$3
KEYPAIR=$4
BUCKET=$5
AWS_ACCESS_KEY=$6
AWS_ACCESS_ID=$7

echo "CLUSTER: $1"
echo "REGION: $2"
echo "ZONES: $3"
echo "KEYPAIR: $4"
echo "BUCKET: $5"
echo "AWS_ACCESS_KEY: $6"
echo "AWS_ACCESS_ID: $7"

#4 Create eks cluster
# Create Cluster: It will take 15 to 20 minutes to create the Cluster Control Plane

sudo eksctl create cluster --name=$CLUSTER \
                      --region=$REGION \
                      --zones=$ZONES \
                      --without-nodegroup;
					  

sleep 25m

#5 Get List of clusters
sudo eksctl get cluster

#6 Create EC2 Keypair
sudo aws ec2 create-key-pair --key-name $KEYPAIR --query 'KeyMaterial' --output text > $KEYPAIR.pem
chmod 400 $KEYPAIR.pem
sudo aws ec2 describe-key-pairs --key-name $KEYPAIR.pem

#7 Create Node Group with additional Add-Ons in Public Subnets
eksctl create nodegroup --cluster=$CLUSTER \
                       --region=$REGION \
                       --name=$CLUSTER-ng-public1 \
                       --node-type=t3.medium \
                       --nodes=2 \
                       --nodes-min=2 \
                       --nodes-max=4 \
                       --node-volume-size=20 \
                       --ssh-access \
                       --ssh-public-key=$KEYPAIR \
                       --managed \
                       --asg-access \
                       --external-dns-access \
                       --full-ecr-access \
                       --appmesh-access \
                       --alb-ingress-access

#8 Make config updates
eksctl utils write-kubeconfig --cluster=$CLUSTER

#9 Create credentials of IAM users for S3
cat > ~/credentials-velero <<EOF
[default]
aws_access_key_id=$AWS_ACCESS_ID
aws_secret_access_key=$AWS_ACCESS_KEY
EOF

#9 install velero in aws
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.1.0 \
    --bucket $BUCKET \
    --backup-location-config region=$REGION \
    --snapshot-location-config region=$REGION \
    --secret-file /tmp/credentials-velero

#10 Make a restore of S3 Cluster in EKS
velero restore create eks-restore-from-backup --from-backup default-namespace-backup
velero restore describe eks-restore-from-backup

#11 Delete EKS Cluster & Node Groups
#eksctl delete nodegroup --cluster=$CLUSTER --name=$CLUSTER-ng-public1
#eksctl delete cluster $CLUSTER
