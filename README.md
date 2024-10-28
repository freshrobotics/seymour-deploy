# seymour-deploy

container tooling for [ros](https://www.ros.org/) deployment

in memory of [seymour papert](https://en.wikipedia.org/wiki/Seymour_Papert)


## dependencies

* linux
* a [recent version of docker](https://docs.docker.com/engine/install/ubuntu/)
* make (`$ sudo apt install build-essential`)


## deploying

the ros packages included in the `./src/` folder will be built and
installed into the container image to be deployed to a target system

this repo does not provide tooling to support incremental development
(if you are interested in incremental development try
[seymour-dev](https://github.com/freshrobotics/seymour-dev))

an excellent way to use the container tooling included here is to stand it up
in a cloud build pipeline to run on pushing a new commit to a git repo and
to push the resulting container image to a container image registry such as
[dockerhub](https://hub.docker.com/)


## multiarch support

docker can be configured to use [qemu](https://www.qemu.org/) to emulate system
architectures that differ from the current system architecture

to install qemu multiarch support on an ubuntu system run:

* `$ make install-multiarch`

then set the "PLATFORM" in the makefile to the architecture to target

for example to target "linux/arm64" (raspberry pi) from a "linux/amd64" (intel)
system uncomment this line in the makefile:

```
#PLATFORM=linux/arm64
```

and comment out this line:

```
PLATFORM=linux/amd64
```

to build and run the docker image in emulation:

* `$ make build`
* `$ make run`


## ros demo

to run the ros talker - listener demo use two terminal windows

in terminal a (`a$`):

* `a$ make build` to build the current source packages inside the container
* `a$ make talker-demo` to run the talker demo in a new container

in terminal b (`b$`):

* `b$ make listener-demo` to run the listener demo in a new container

you should see output in terminal a similar to:

```
[INFO] [1722471491.552201505] [talker]: Publishing: 'Hello World: 1'
[INFO] [1722471492.552257864] [talker]: Publishing: 'Hello World: 2'
[INFO] [1722471493.552201928] [talker]: Publishing: 'Hello World: 3'
[INFO] [1722471493.552201928] [talker]: Publishing: 'Hello World: 4'
```

and output in terminal b similar to:

```
[INFO] [1722471494.552915449] [listener]: I heard: [Hello World: 3]
[INFO] [1722471495.552809036] [listener]: I heard: [Hello World: 4]
```
