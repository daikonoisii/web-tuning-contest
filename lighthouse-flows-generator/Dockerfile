# Dockerfile for Puppeteer + Lighthouse on AWS Lambda
FROM public.ecr.aws/lambda/nodejs:18

RUN yum install -y \
    atk \
    cups-libs \
    libXcomposite \
    libXcursor \
    libXdamage \
    libXext \
    libXi \
    libXrandr \
    libXScrnSaver \
    libXtst \
    pango \
    alsa-lib \
    libX11 \
    libXrender \
    xorg-x11-fonts-Type1 \
    xorg-x11-fonts-misc \
    gtk3 \
    nss \
    wget \
    tar \
    unzip \
    && yum clean all

COPY package*.json ./
RUN npm install

COPY . .

CMD ["dist/commands/generate.handler"]
