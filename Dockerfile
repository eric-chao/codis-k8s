# Get codis source code first.
# git clone https://github.com/CodisLabs/codis.git

FROM golang:1.8

ENV GOPATH /gopath
ENV CODIS  ${GOPATH}/src/github.com/CodisLabs/codis
ENV PATH   ${GOPATH}/bin:${PATH}:${CODIS}/bin

COPY . ${CODIS}

RUN mv ${CODIS}/sources.list /etc/apt/ \
	&& apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 3B4FE6ACC0B21F32 \
	&& apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 40976EAF437D05B5 \
	&& apt-get update -y \
	&& apt-get install autoconf -y --force-yes

RUN make -C ${CODIS} distclean
RUN make -C ${CODIS} build-all

WORKDIR /codis
