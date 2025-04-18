import json
import boto3

firehose = boto3.client('firehose')

# process data on lambda
def lambda_handler(event, context):
    energy_data = {
        "timestamp": event.get("timestamp"),
        "kwh": event.get("kwh")
    }
    
    # Send data to Kinesis Firehose
    firehose.put_record(
        DeliveryStreamName='energy-firehose-stream',
        Record={'Data': json.dumps(energy_data).encode('utf-8')}
    )
    return {"status": "success"}