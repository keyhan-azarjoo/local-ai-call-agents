// sipgw: connects people's existing phone numbers to LocalAILine through their own SIP
// provider, with no hardware.
//
// For every line it signs in (SIP REGISTER) to the person's provider and keeps that sign-in
// alive. When the number gets a call, the provider rings the gateway, which hands the call to
// LiveKit SIP, where the agent answers. When the agent calls out, LiveKit hands the call to the
// gateway, which places it through the line's provider with the line's own number. Only
// signalling passes through here; the audio goes directly between the provider and LiveKit.
//
// Lines are added and removed over a small HTTP control API. See README.md.
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/config"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/gateway"
)

var version = "dev"

func main() {
	path := flag.String("config", os.Getenv("LL_SIPGW_CONFIG"), "YAML or JSON config file (or LL_SIPGW_CONFIG)")
	showEnv := flag.Bool("env", false, "list the environment variables and exit")
	showVersion := flag.Bool("version", false, "print the version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Println("sipgw", version)
		return
	}
	if *showEnv {
		for _, e := range config.EnvVars {
			fmt.Printf("%-34s %s\n", e.Env, e.Key)
		}
		return
	}

	cfg, err := config.Load(*path, os.LookupEnv)
	if err != nil {
		fmt.Fprintln(os.Stderr, "sipgw: configuration problem:")
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	log := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level(cfg.LogLevel)}))

	gw, err := gateway.New(cfg, log, gateway.Options{})
	if err != nil {
		log.Error("could not start", "error", err)
		os.Exit(1)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := gw.Run(ctx); err != nil {
		log.Error("stopped with an error", "error", err)
		os.Exit(1)
	}
}

func level(s string) slog.Level {
	switch strings.ToLower(s) {
	case "debug":
		return slog.LevelDebug
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	}
	return slog.LevelInfo
}
