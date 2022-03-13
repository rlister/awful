build:
	docker build . -t awful

run:
	docker run -it -e AWS_REGION -e AWS_SESSION_TOKEN -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY awful sh
