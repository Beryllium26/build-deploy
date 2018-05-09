#!/usr/bin/perl

$ENV{JAVA_HOME}="/usr/lib/jvm/java-oracle";
$ENV{PATH}="/usr/lib/jvm/java-oracle/bin:/usr/local/bin:/usr/bin:/bin";

# $rev to contain eventual svn version if older release is required
$rev="";
#system("clear");

## Project specific names
$mod="proj";
$antmod="proj";
$shmod = "proj";
$ovhost = "ovp-proj";
#$lcmod = lc($antmod);
$lcmod = lc($mod);

#check we're on build box
$thishost=`cat /etc/hostname`;
chomp $thishost;
if ( $thishost !~ /proj07-build.default.proj.uk0.bigv.io/ ) {
	print "\n$thishost: This script needs to run on build box!! \n";
	exit 0;
}

@tomcathosts=`grep ${ovhost}\* /etc/hosts | awk '{print \$2}'`;
if ( @tomcathosts == "" ) {
	print "\n  No tomcat hosts were identified in hosts file! exiting.\n";
	exit 1;
} else {
	print "\n Tomcat hosts are:\n @tomcathosts \n";
}



print  "\nSelect build Environment:\n";
while(not $buildenv =~ /[123]/) {
	print "CIT/Test [1], Production [2], Admin [3]  ?: ";
	$buildenv = <STDIN>;
}
chomp($buildenv);

print "\nVersion to be deployed? e.g. 2.10.9[-SNAPSHOT]: ";
while (not $mvn_version =~ /^\d+\.\d+\.\d+(|-(-|_|\w+))$/) {
    print "enter maven version : ";
    $mvn_version = <STDIN>;
}
chomp($mvn_version);

$buildenvcho = "Local";
@tomcathosts="localhost";

if ( $buildenv == "1") 
 {
	@tomcathosts=`grep ${ovhost} /etc/hosts | grep cit | awk '{print \$2}'`;
	$buildenvcho = "CIT";
	$mvn_env = "test";
	$senvk = "t";
	$antop="warTest";
	$antjar="${antmod}Jar";
    $s3prefix="snapshot";
    $s3war = "proj-web-${mvn_version}.war"
 }
if ( $buildenv == "2")
 {
	@tomcathosts=`grep -E "${ovhost}..[pd]r" /etc/hosts | awk '{print \$2}'`;
	$buildenvcho = "Production";
	$mvn_env = "prod";
	$senvk = "p";
	$antop="warProd";
	$antjar="${antmod}Jar";
    $s3prefix="release";
    $s3war = "proj-web-${mvn_version}.war"
 }

if ( $buildenv == "3")
 {
        @tomcathosts=`grep -E "${ovhost}..admin" /etc/hosts | awk '{print \$2}'`;
        $buildenvcho = "Admin";
	    $mvn_env = "admin";
        $senvk = "p";
        $antop="warAdmin";
        $antjar="${antmod}Jar";
        $s3prefix="release";
        $s3war = "proj-web-${mvn_version}.war"
 }

##################################################
$sshk="/usr/bin/ssh -i /home/build/.ssh/${shmod}${senvk}";
$scpk="/usr/bin/scp -i /home/build/.ssh/${shmod}${senvk}";
$s3bucket_uri = "s3://proj-s3-euwest1-maven-ci/${s3prefix}/uk/co/proj/proj-web/${mvn_version}/";
$s3warcheck = `/usr/bin/envdir /var/opt/build/ aws s3 ls $s3bucket_uri | awk '/${s3war}\$/ {print \$4}'`;
chomp($s3warcheck);

if ( $buildenvcho eq 'Production' ) {
   print " \n env = $buildenvcho \n";
   if ( $s3warcheck =~ /${s3war}/ ) {
      print "\n $s3warcheck found in $s3bucket_uri ! roll on...";
   }
   else
   {
       print "\n ${s3warcheck} was not found in $s3bucket_uri !\n  Please check if this war file is available in S3 $mvn_env !";
       exit 1;
   }
}
else
{
   $s3maven_metadata = `/usr/bin/envdir /var/opt/build/ aws s3 ls $s3bucket_uri | awk '/maven-metadata.xml\$/ {print \$4}'`;
   chomp($s3maven_metadata);
   if ( $s3maven_metadata eq '' ) {
      print "\n maven-metadata.xml not found | $s3maven_metadata \n\n";
      exit 1;
   }
}

##################################################
$wardir="/build/wars";
$workdir="/build/work/";
$moddir="/build/exp/proj/build"; # /build/exp/fn/trunk
$mvn_rundir="/build/exp/proj/web";  # dir Maven needs to run in

$ans3="2";
 

if (-d $workdir ) {
	if ( $buildenvcho eq 'CIT' ) {
	   print "  Retrieving maven-metadata.xml from S3 to extract latest version \n";
	   system("/usr/bin/envdir /var/opt/build/ aws s3 cp ${s3bucket_uri}maven-metadata.xml ${workdir}maven-metadata.xml");
	   $s3war_version = `grep -A 1 "extension>war" ${workdir}maven-metadata.xml | grep value | sed -e 's/<//g;s/>//g;s/value//g;s:/::g;s/ //g'`; 
	   chomp($s3war_version);
	   print " Version extracted from maven-metadata.xml: $s3war_version \n\n";
	   $s3war = "proj-web-${s3war_version}.war";
	}
           $s3fullp = "${s3bucket_uri}${s3war}";
	   $localfullp = "$wardir/${s3war}";
	   print "  Maven S3 repo export \n";
	   sleep(1);
	   system("/usr/bin/envdir /var/opt/build/ aws s3 cp ${s3fullp} ${wardir}/${s3war}");
		if ( ! -e "${localfullp}") {
		   print "\n\n Copy from S3 failed? check access from cmd line\n";
		   exit 1;
		}

		#sleep(1);
		# Depending on user's choice test/prod/demo/local hosts ...
	        print "\n\n$buildenvcho hosts defined in hosts file are:\n @tomcathosts\n\n";
		print "OpenVPN initialization is required for each host.\n";
	   	print " If deploying to 'all' hosts you will need to enter your VPN credentials after the 1st deploy again to set-up a new tunnel.\n";
		print "which host should $lcmod.war be deployed to?\n";
		#while(not $thost =~ /\w{3}tom\d+|all|localhost/)
		while(not $thost =~ /ovp-proj\w{2}|all|localhost/)
 		 {
        		print "[enter target hostname / all] : ";
        		$thost=<STDIN>;
 		 }
		chomp($thost);
		if ($thost ne "all") { @tomcathosts=$thost; }
		if ($thost ne "localhost")
		{
		 foreach (@tomcathosts) {
	           chomp;
		   $ovpntunn = `/usr/bin/pgrep -f $_.conf`;
		   # check if ovpn tunnel is up
		   if ( not $ovpntunn == "") { 
			print "vpn tunnel is up, attempting termination\n";
			system("/usr/bin/pkill -f $_.conf");
		   }

		   if ($_ ne "ovp-proj10") {
		     # start ovpn tunnel
		     print "OpenVPN initialization for $_ \n";
		     if(system("/usr/local/sbin/openvpn --config /etc/openvpn/$_.conf --daemon --askpass --auth-user-pass --auth-nocache") !=0) { die("OpenVPN failed to launch");}
		   }

		   ## check if host is reachable ...
		   print "\n\n Is $_ pingable ... ?\n";
		   $hostliv = system("ping -c 1 -q $_ | grep transm | awk '{print $6}'");
		   if ( not $hostliv = "0%") {
		       print "\n ** $_ unreachable - unable to deploy!\n";
		       next;
	           }
		   print "\n deploying $lcmod.war to $_\n";
		   @checkssh = `telnet $_ 22 < /dev/null`;
		   chomp $checkssh[1];
	           print " ---- checkssh[1]: $checkssh[1]\n";
		   if ( not $checkssh[1] =~ /Connected/) {
			print "\n Sorry we're unable to ssh to $_\n - Deployment halted\n";
			next;
		   }

		   print "\n Shutting down Tomcat on $_ ...\n";
		   system("$sshk $_ '/apps/tomcat/bin/shutdown.sh'");
		   # give tomcat a chance to shutdown
		   sleep(6);
		   system("$sshk $_ '/usr/bin/pkill java'");
		   print " \nRemoving existing $lcmod app from target's webapps ROOT dir\n";
		   system("$sshk $_ 'rm  /apps/tomcat/webapps/ROOT.war'"); 
		   system("$sshk $_ 'rm -r  /apps/tomcat/webapps/ROOT/'"); 
		   system("$sshk $_ 'rm -r  /apps/tomcat/work/Catalina/*'"); 
		   system("$sshk $_ 'rm -r  /apps/tomcat/temp/'");
		   system("$sshk $_ 'mkdir  /apps/tomcat/temp && chmod 0750 /apps/tomcat/temp'");
		   print "\n Copying and deploying $lcmod.war to $_:/apps/tomcat/webapps/ROOT ...\n";
		   system("$scpk $wardir/${s3war} $_:/apps/tomcat/webapps/ROOT.war");
		   system("$scpk $wardir/${s3war} $_:");

		   system("$sshk $_ '/apps/tomcat/bin/startup.sh'");
		   print "\n\n ** Deployment for $_ completed!\n";
		   print "\n Check output from catalina.out below... waiting ~ 20s... \n\n";
		   sleep(20);
		   system("$sshk $_ 'tail -30 /apps/tomcat/logs/catalina.out'");
		   # 
		   # stops openvpn
		   system("/usr/bin/pkill -SIGTERM -f '/usr/local/sbin/openvpn --config /etc/openvpn/$_.conf --daemon'");
		   sleep(7);
		 }
		}  # 
		if ($thost =~ /localhost/)
		{
		print "\n Shutting down Tomcat on $_ ...\n";
                   system("tail -30 /apps/tomcat/logs/catalina.out");

		}

	        
	        
}
else {
  	print "\n Work directory not found!\n";
}




