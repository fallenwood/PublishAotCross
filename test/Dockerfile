# linux x64 -> arm64 docker example
FROM mcr.microsoft.com/dotnet/sdk:9.0 as build
WORKDIR /src
COPY . .
RUN apt update -y && apt install bash curl xz-utils llvm -y
RUN curl https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz -O && \
  tar xf zig-linux-x86_64-0.13.0.tar.xz && \
  mv zig-linux-x86_64-0.13.0 /usr/local && \
  ln -s /usr/local/zig-linux-x86_64-0.13.0/zig /usr/local/bin/zig

RUN dotnet publish -c Release -r linux-arm64 -o output

FROM mcr.microsoft.com/azurelinux/distroless/base:3.0.20241005-arm64 as base
WORKDIR /app
COPY --from=build /src/output/Hello /app

CMD ["./Hello"]
