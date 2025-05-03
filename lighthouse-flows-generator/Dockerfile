# Dockerfile for Puppeteer + Lighthouse on AWS Lambda
FROM --platform=linux/amd64 public.ecr.aws/lambda/nodejs:18

# Chrome RPM を落としてインストール
ADD https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm /tmp/chrome.rpm
RUN yum install -y /tmp/chrome.rpm \
    && yum clean all \
    && rm -f /tmp/chrome.rpm

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
RUN npm ci

COPY . .
