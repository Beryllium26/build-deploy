# build-deploy

Perl scripts used to build and deploy java war files to application servers running Tomcat.
<p>Early scripts pulled a code release from SVN, and more recently the codebase was pulled from an S3 bucket.
<p>OpenVPN is used to deploy the code to remote nodes, with user authentication (individual certificates created for each developer) and a unique deploy key for each environment.
