package main

import (
 "crypto/tls"
 "crypto/x509"
 "fmt"
 "io"
 "net/http"
 "net/url"
 "os"
 "path/filepath"
 "strconv"
 "time"
)

func roots() *x509.CertPool {
 pool,_:=x509.SystemCertPool(); if pool==nil {pool=x509.NewCertPool()}
 for _,d:=range []string{"/system/etc/security/cacerts","/apex/com.android.conscrypt/cacerts"} {
  entries,_:=os.ReadDir(d)
  for _,e:=range entries {b,_:=os.ReadFile(filepath.Join(d,e.Name()));pool.AppendCertsFromPEM(b)}
 }
 return pool
}

func run(a []string) error {
 if len(a)!=3 {return fmt.Errorf("usage: agh-http-fetch HTTPS_URL DEST MAX_BYTES")}
 u,e:=url.Parse(a[0]);if e!=nil||u.Scheme!="https"||u.Host==""||u.User!=nil{return fmt.Errorf("invalid HTTPS URL")}
 n,e:=strconv.ParseInt(a[2],10,64);if e!=nil||n<1||n>524288{return fmt.Errorf("invalid size limit")}
 t:=&http.Transport{TLSClientConfig:&tls.Config{RootCAs:roots(),MinVersion:tls.VersionTLS12}}
 c:=&http.Client{Transport:t,Timeout:90*time.Second,CheckRedirect:func(r *http.Request,v []*http.Request)error{if len(v)>5||r.URL.Scheme!="https"{return fmt.Errorf("unsafe redirect")};return nil}}
 r,e:=c.Get(a[0]);if e!=nil{return e};defer r.Body.Close()
 if r.StatusCode!=200{return fmt.Errorf("HTTP %d",r.StatusCode)}
 f,e:=os.OpenFile(a[1],os.O_WRONLY|os.O_CREATE|os.O_EXCL,0600);if e!=nil{return e}
 ok:=false;defer func(){f.Close();if !ok{os.Remove(a[1])}}()
 count,e:=io.Copy(f,io.LimitReader(r.Body,n+1));if e!=nil{return e};if count<1||count>n{return fmt.Errorf("invalid response size")}
 if e=f.Close();e!=nil{return e};ok=true;return nil
}
func main(){if e:=run(os.Args[1:]);e!=nil{fmt.Fprintln(os.Stderr,e);os.Exit(1)}}
