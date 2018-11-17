package thread

import (
	"fmt"
	"os"
	"runtime"
)

func init() {
	fmt.Println("Initializing thread")
	runtime.LockOSThread()
}

func Beep(ch chan bool, pid chan int) {
	pid <- os.Getpid()
	for {
	}
	ch <- true
}
