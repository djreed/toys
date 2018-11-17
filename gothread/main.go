package main

import (
	"os"
	"runtime"
	"syscall"
	"time"
)

func main() {
	runtime.LockOSThread()
	println("Hi from ", syscall.Gettid())
	println("Mama PID ", os.Getpid())

	go func() {
		runtime.LockOSThread()
		println("Hi from ", syscall.Gettid())
		println("Child PID ", os.Getpid())
	}()
	time.Sleep(500 * time.Millisecond)
	println("Bye from ", syscall.Gettid())
}

// func init() {
// 	fmt.Println("Initializing main")
// 	runtime.LockOSThread()
// }

// func main() {
// 	n := runtime.NumCPU()
//
// 	if n < 2 {
// 		log.Fatal("Atleast 2 CPUs needed")
// 	}
//
// 	// Expose CPUs to scheduler
// 	runtime.GOMAXPROCS(n)
// 	fmt.Println("Main PID:", os.Getpid())
//
// 	ended, err := Timeout(100)
// 	fmt.Println(ended, err)
// }
//
// //Get the name of this Player
// func Timeout(ms int) (bool, error) {
// 	fmt.Println("Timeout PID:", os.Getpid())
//
// 	timeout := time.Duration(ms) * time.Millisecond
//
// 	ch := make(chan bool, 1)
// 	pid := make(chan int, 1)
//
// 	go thread.Beep(ch, pid)
//
// 	child := <-pid
// 	fmt.Println("Child PID inside Timeout:", child)
//
// 	proc, err := os.FindProcess(child)
// 	fmt.Println("Proc, err", proc, err)
//
// 	select {
// 	case res := <-ch:
// 		return res, nil
// 	case <-time.After(timeout):
// 		proc.Kill()
// 		return false, errors.New("Big Gay")
// 	}
// }
