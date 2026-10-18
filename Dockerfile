FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY HospitalFlow/HospitalFlow.csproj HospitalFlow/
RUN dotnet restore HospitalFlow/HospitalFlow.csproj
COPY HospitalFlow/ HospitalFlow/
RUN dotnet publish HospitalFlow/HospitalFlow.csproj -c Release --no-restore -o /out /p:UseAppHost=false
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /out .
ENV ASPNETCORE_ENVIRONMENT=Production
ENV ASPNETCORE_URLS=https://+:8443
USER $APP_UID
EXPOSE 8443
ENTRYPOINT ["dotnet", "HospitalFlow.dll"]
