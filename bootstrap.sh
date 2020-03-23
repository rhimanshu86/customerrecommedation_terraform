
#!/bin/bash
echo `sudo pip install awscli --force-reinstall --upgrade`
echo `aws s3 cp s3://himanshu-assesment-bucket/assesment_solution.zip /tmp/ --region eu-west-1`
echo `unzip /tmp/assesment_solution.zip -d /tmp/assesment_solution`
sleep 10
echo `aws s3 cp s3://himanshu-assesment-bucket/spark-test-data.json /tmp/ --region eu-west-1`
echo `ls /tmp/spark-test-data.json`
echo `chmod 777 /tmp/assesment_solution/*`

echo " runs well"
