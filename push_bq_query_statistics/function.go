package push_bq_query_statistics

import (
	"bytes"
	"context"
	"net/http"
	"net/url"
	"os"
	"path"
	"time"

	"cloud.google.com/go/pubsub"
	"github.com/gogo/protobuf/proto"
	"github.com/golang/snappy"
	"github.com/grafana/loki/pkg/logproto"
)

// Push pushes Cloud Logging messages to Loki by protocol buffers.
func Push(ctx context.Context, m pubsub.Message) error {
	reqData, err := genPushRequest(m.Data)
	u, err := url.Parse(os.Getenv("LOKI_URL"))
	if err != nil {
		return err
	}
	u.Path = path.Join(u.Path, "loki", "api", "v1", "push")
	req, err := http.NewRequest("POST", u.String(), bytes.NewReader(reqData))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-protobuf")
	req.Header.Set("X-Scope-OrgID", os.Getenv("LOKI_TENANT_ID"))
	client := &http.Client{}
	res, err := client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if err != nil {
		return err
	}

	return nil
}

func genPushRequest(msg []byte) ([]byte, error) {
	var entries []logproto.Entry
	e := logproto.Entry{Timestamp: time.Now(), Line: string(msg)}
	entries = append(entries, e)
	var streams []logproto.Stream
	stream := &logproto.Stream{
		Labels:  os.Getenv("LOKI_LABELS"),
		Entries: entries,
	}
	streams = append(streams, *stream)
	pushReq := &logproto.PushRequest{
		Streams: streams,
	}
	buf, err := proto.Marshal(pushReq)
	if err != nil {
		return nil, err
	}
	buf = snappy.Encode(nil, buf)
	return buf, nil
}
