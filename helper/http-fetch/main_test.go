package main
import (
 "context"
 "encoding/binary"
 "net"
 "net/http"
 "net/http/httptest"
 "os"
 "path/filepath"
 "testing"
 "time"
)
func TestRejectUntrustedTLS(t *testing.T){
 s:=httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){w.Write([]byte("rules"))}));defer s.Close()
 p:=filepath.Join(t.TempDir(),"rules")
 if run([]string{s.URL,p,"100"})==nil{t.Fatal("untrusted TLS accepted")}
 if _,e:=os.Stat(p);!os.IsNotExist(e){t.Fatal("failed fetch left destination")}
}
func TestRejectHTTP(t *testing.T){if run([]string{"http://example.org",filepath.Join(t.TempDir(),"rules"),"100"})==nil{t.Fatal("plaintext accepted")}}

func TestExplicitDNSDoesNotUseSystemResolver(t *testing.T) {
 dns,e:=net.ListenPacket("udp","127.0.0.1:0"); if e!=nil {t.Fatal(e)}; defer dns.Close()
 listener,e:=net.Listen("tcp","127.0.0.1:0"); if e!=nil {t.Fatal(e)}; defer listener.Close()
 t.Setenv("AGH_FETCH_DNS",dns.LocalAddr().String())
 go func(){for {b:=make([]byte,1500); n,peer,e:=dns.ReadFrom(b); if e!=nil{return}; q:=b[:n]; end:=12; for q[end]!=0 {end+=int(q[end])+1}; end++; typ:=binary.BigEndian.Uint16(q[end:end+2]); r:=append([]byte(nil),q[:end+4]...); r[2]=0x81; r[3]=0x80; r[6]=0; r[7]=0
 if typ==1 {r[7]=1;r=append(r,0xc0,0x0c,0,1,0,1,0,0,0,10,0,4,127,0,0,1)};dns.WriteTo(r,peer)}}()
 _,port,_:=net.SplitHostPort(listener.Addr().String())
 ctx,cancel:=context.WithTimeout(context.Background(),3*time.Second);defer cancel()
 conn,e:=fetchDial(ctx,"tcp","module-fetch-test.invalid:"+port);if e!=nil{t.Fatal(e)};conn.Close()
}
