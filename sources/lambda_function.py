import boto3
import json
import os

def lambda_handler(event, context):
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    stopped_instances = []
    failed_instances = []
    ec2_global = boto3.client('ec2')

    # Lấy danh sách tất cả các regions
    regions = [region['RegionName'] for region in ec2_global.describe_regions()['Regions']]

    for region in regions:
        print(f'Checking region: {region}')
        ec2 = boto3.client('ec2', region_name=region)
        
        filters = [
            {
                'Name': 'tag:Type',
                'Values': ['Lab']
            },
            {
                'Name': 'instance-state-name',
                'Values': ['running']
            }
        ]

        try:
            instances = ec2.describe_instances(Filters=filters)
        except Exception as e:
            print(f"Error checking instances in {region}: {e}")
            continue
        
        instance_ids = []
        for reservation in instances['Reservations']:
            for instance in reservation['Instances']:
                instance_ids.append(instance['InstanceId'])

        if instance_ids:
            try:
                ec2.stop_instances(InstanceIds=instance_ids)
                print(f'Successfully stopped instances in {region}: {instance_ids}')
                stopped_instances.extend([f"Successfully stopped EC2 instance {instance_id} in region {region}" for instance_id in instance_ids])
            except Exception as e:
                print(f"Failed to stop instances in {region}: {e}")
                failed_instances.extend([f"Failed to stop EC2 instance {instance_id} in region {region}" for instance_id in instance_ids])

    # Gửi SNS thông báo nếu có instance bị stop thành công
    if stopped_instances and sns_topic_arn:
        sns = boto3.client('sns')
        success_message = "Successfully stopped EC2 instances:\n" + "\n".join(stopped_instances)
        try:
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject="EC2 Auto Stop Notification - Success",
                Message=success_message
            )
            print(f'Sent SNS notification with {len(stopped_instances)} successfully stopped instances.')
        except Exception as e:
            print(f"Error sending SNS notification for success: {e}")

    # Gửi SNS thông báo nếu có instance tắt thất bại
    if failed_instances and sns_topic_arn:
        sns = boto3.client('sns')
        fail_message = "Failed to stop EC2 instances:\n" + "\n".join(failed_instances)
        try:
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject="EC2 Auto Stop Notification - Failure",
                Message=fail_message
            )
            print(f'Sent SNS notification with {len(failed_instances)} failed instances.')
        except Exception as e:
            print(f"Error sending SNS notification for failure: {e}")

    # Nếu không có instance nào bị stop
    if not stopped_instances and not failed_instances:
        print('No instances stopped or SNS topic not configured.')
