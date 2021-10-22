workflow Ping_p{
  Param($comp_ips)
  foreach -parallel ($ip in $comp_ips){
    echo $ip, "-",  ([System.Net.NetworkInformation.Ping]::new().Send($ip)).Status
    }
}
