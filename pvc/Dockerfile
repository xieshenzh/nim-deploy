FROM --platform=linux/x86_64 ubuntu AS cli

ENV NGC_VERSION 3.43.0
ENV NGC_URL https://api.ngc.nvidia.com/v2/resources/nvidia/ngc-apps/ngc_cli/versions/${NGC_VERSION}/files/ngccli_linux.zip

RUN apt -y update && apt -y upgrade && apt -y install wget unzip

RUN echo ${NGC_URL}

RUN wget --content-disposition ${NGC_URL} -O ngccli_linux.zip \
    && unzip ngccli_linux.zip

FROM --platform=linux/x86_64 ubuntu

COPY --from=cli /ngc-cli /usr/local/bin

RUN chmod u+x /usr/local/bin/ngc

CMD ngc registry model download-version --dest $MODEL_CACHE_PATH $MODEL_VERSION

