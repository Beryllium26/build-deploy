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
 }
if ( $buildenv == "2")
 {
	@tomcathosts=`grep -E "${ovhost}..[pd]r" /etc/hosts | awk '{print \$2}'`;
	$buildenvcho = "Production";
	$mvn_env = "prod";
	$senvk = "p";
	$antop="warProd";
	$antjar="${antmod}Jar";
 }

if ( $buildenv == "3")
 {
        @tomcathosts=`grep -E "${ovhost}..admin" /etc/hosts | awk '{print \$2}'`;
        $buildenvcho = "Admin";
	$mvn_env = "admin";
        $senvk = "p";
        $antop="warAdmin";
        $antjar="${antmod}Jar";
 }

$sshk="/usr/bin/ssh -i /home/build/.ssh/${shmod}${senvk}";
$scpk="/usr/bin/scp -i /home/build/.ssh/${shmod}${senvk}";

print  "\nSVN release we need to export:\n";
while(not $latestans =~ /^[ynYN]$/) {
	print " Use latest version (trunk)? [y/n]: ";
	$latestans = <STDIN>;
}
chomp($latestans);

if(($latestans eq "n") || ($mod eq "N")) 
 {
	# older snapshot?
	while(not $brtr =~ /branches|trunk/) { print " [branches/trunk]? : "; $brtr = <STDIN>; } 
	 chomp($brtr); 
	if ($brtr eq "branches")
	 {

		#while(not $tag =~ /\w+\.\d{2}\.\d{2}/) { print " Enter branch name: "; $tag= <STDIN>; }
		while(not $tag =~ /\w+/) { print " Enter branch name: "; $tag= <STDIN>; }
		chomp($tag);
		$svnpath="$mod/branches/$tag";
		$svnexpdir="/build/exp/$mod/branches";
		$spath="branches/$tag";
	 }
	else {
		$svnexpdir="/build/exp/$mod";
		$svnpath="$mod/trunk";
		$spath="trunk";
 	 }
	while(not $rev =~ /\d{2,6}|\n/)  { print " Enter svn revision No. ([return] for latest): "; $rev = <STDIN>; }
	chomp($rev);
	if ($rev == "")
	  { 
		$svnlist="svn list -v file:///home/svn/src/$svnpath";
		$svngrev=`svn list -v file:///home/svn/src/$mod | awk '/$brtr/ {print \$1}'`;
		chomp($svngrev);
		$svnrev="$tag-$svngrev";
		$svnexp="svn export file:///home/svn/src/$mod/$spath -r $svngrev";
	  }
	else
	  {
		$svnlist="svn list -v file:///home/svn/src/$svnpath -r $rev";
		$svnexp="svn export file:///home/svn/src/$mod/$spath -r $rev";
		$svnrev=$tag-$rev;
	  }
	# list user
	print "$svnlist\n";
	system("$svnlist");
	# check if valid proj release or $svnloc empty
	$svnloc = `$svnlist | awk 'NR==1 {print \$0}'`;
	chomp($svnloc);
	print "\nsvnloc[0]: -$svnloc-  \n";

	#  if (($svnloc =~ /Unable to find repository/) || ($svnloc =~ /No such revision/) || ($svnloc == ""))
	if ($svnloc == "")
	   {
		print "\n\n Invalid SVN location/revision - exiting script!\n";
		exit 0;
	   }

	while(not $cont =~ /[ynYN]/) { print " Continue? [y/n]: "; $cont=<STDIN>; }
	chomp($cont);
	if (($cont eq "n") || ($mod eq "N"))
	 {
		exit 0;
	 }
 }
else
 {
	# extract the latest rev to be exported
	$svnexpdir="/build/exp/$mod";
	$svnpath="$mod/trunk";
	$svnexp="svn export file:///home/svn/src/$mod/trunk";
	$svnrev=`svn list -v file:///home/svn/src/$mod/ | awk '/trunk/ {print \$1}'`;
	chomp($svnrev);
 }
$wardir="/build/wars";
$workdir="/build/work/";
$moddir="/build/exp/$svnpath/build"; # /build/exp/fn/trunk
$mvn_rundir="/build/exp/$svnpath/web";  # dir Maven needs to run in

$ans3="2";
 

if (-d $workdir ) {
   if ($ans3 == "2")
   {
	if (-d $svnexpdir) {
	   print "\nExporting svn repository to compile $mod module.\n";
	   print "  SVN repo export directory $svnexpdir clean-up\n";
	   sleep(1);
	   system("rm -fr $svnexpdir 2>/dev/null ; rm -fr $workdir/$mod; mkdir $workdir/$mod ");
		if (-d $svnexpdir) {
		   print "\n\n Clean-up of $svnexpdir failed... check permissions?\n";
		   exit 1;
		}
	}
	system("mkdir -p $svnexpdir");
	print "  Making local copy of projects repo with $svnexp ...\n";
	sleep(1);
	system("cd $svnexpdir; $svnexp");
	if (-e "$mvn_rundir/pom.xml") {
		print "\n\nGreat! Found pom.xml file in $mvn_rundir \n";		
		print "\n Extracting version No from pom.xml \n";
                $web_war_ver=`/usr/bin/head -10 $mvn_rundir/pom.xml | grep version | tail -1| sed -e 's:version::g' -e 's:<>::' -e 's:</>::' -e 's:    ::'`;
		chomp($web_war_ver);
	        #$web_war_name="${lcmod}-webapp-${web_war_ver}.war";
		$web_war_name="${lcmod}-web-${web_war_ver}.war";
		chomp($web_war_name);
		print "Now building war file ($web_war_name) in $mvn_rundir/target...\n\n";
		#system ("awk -v var=3306 '{  gsub(/3308/,var,\$0); print }' $moddir/WEB-INF/struts-config.xml > tempfile.xml");
		#print ("\n******cp tempfile.xml $moddir/WEB-INF/struts-config.xml");
		#system("cp tempfile.xml $moddir/WEB-INF/struts-config.xml");
		sleep(1);
		# using maven to build war
		system("cd $mvn_rundir && /usr/bin/mvn -P $mvn_env -DskipTests=true package");
		## temp fix to get correct build_linux.xml ...
		#system("cd $moddir; ant $antjar -f ./build.xml");
		#system("cd $moddir; ant $antop -f ./build.xml");
		if (not -e  "$mvn_rundir/target/$web_war_name") {
		   print "\n\n ** $web_war_name: file not found in target/ \n";
		   exit 1;
	        }
		else {
		   print "\n\n ** $web_war_name built in target/ \n";
		   system("cp -p $mvn_rundir/target/$web_war_name $wardir/$lcmod-$svnrev.war");
		}
	}
	else {
		print "Error: Couldn't find (linux) pom.xml file in $mvn_rundir \n - Exiting! \n";
		exit 1;
	}
		#sleep(1);
   } # if ($ans3 == "2")
   else
   {
       print "\nBy-passing build stage - Deploying already built $lcmod-$svnrev.war to target hosts\n";		
   }
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
		   system("$sshk $_ 'rm   /apps/tomcat/webapps/ROOT.war'"); 
		   system("$sshk $_ 'rm -r  /apps/tomcat/webapps/ROOT/'"); 
		   system("$sshk $_ 'rm -r  /apps/tomcat/work/Catalina/*'"); 
		   system("$sshk $_ 'rm -r  /apps/tomcat/temp/'");
		   system("$sshk $_ 'mkdir  /apps/tomcat/temp && chmod 0750 /apps/tomcat/temp'");
		   print "\n Copying and deploying $lcmod.war to $_:/apps/tomcat/webapps/ROOT ...\n";
		   system("$scpk $wardir/$lcmod-$svnrev.war $_:/apps/tomcat/webapps/ROOT.war");
		   system("$scpk $wardir/$lcmod-$svnrev.war $_:");

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




