# USAGE:
# docker build . -t autodoc
# docker run --mount src=`pwd`,target=/app,type=bind --network=host --env-file ./env -v $pwd:/app autodoc

FROM ubuntu:18.04

WORKDIR /app

RUN apt-get update

RUN apt-get install -y libdbi-perl \
  libhtml-template-perl libterm-readkey-perl \
  libdbd-pg-perl make

COPY . .

RUN make install

ENV DATABASE=app \
  HOST=localhost \
  PORT=port \
  USER=app \
  PASSWORD=password

CMD postgresql_autodoc -d ${DATABASE} \
  -h ${HOST} \
  -p ${PORT} \
  -u ${USER} \
  --password=${PASSWORD}
