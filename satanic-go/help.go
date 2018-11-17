package main

// int ident(int n)
// {
//	    return n;
// }
import "C"

import (
	"fmt"
	"os"
	"strconv"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	c_n := C.int(n) // Normal Integers? Not good enough.
	fmt.Println(C.ident(c_n))
}
