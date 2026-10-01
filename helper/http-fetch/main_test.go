package main
import (
 "net/http"
 "net/http/httptest"
 "os"
 "path/filepath"
 "testing"
)
func TestRejectUntrustedTLS(t *testing.T){
 s:=httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){w.Write([]byte("rules"))}));defer s.Close()
 p:=filepath.Join(t.TempDir(),"rules")
 if run([]string{s.URL,p,"100"})==nil{t.Fatal("untrusted TLS accepted")}
 if _,e:=os.Stat(p);!os.IsNotExist(e){t.Fatal("failed fetch left destination")}
}
func TestRejectHTTP(t *testing.T){if run([]string{"http://example.org",filepath.Join(t.TempDir(),"rules"),"100"})==nil{t.Fatal("plaintext accepted")}}
