package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"

	"github.com/vrob01/pocketlarder/server/internal/larder"
)

func main() {
	ctx, _ := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	os.Exit(larder.Run(ctx, os.Args[1:], os.Getenv, os.Stdout, os.Stderr))
}
