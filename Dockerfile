FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY HospitalFlow.csproj VERSION release.json ./
RUN dotnet restore HospitalFlow.csproj
COPY . .
ARG SOURCE_REVISION_ID
RUN dotnet publish HospitalFlow.csproj -c Release --no-restore -o /out /p:UseAppHost=false /p:SourceRevisionId=${SOURCE_REVISION_ID}
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /out .
ENV ASPNETCORE_ENVIRONMENT=Production
ENV ASPNETCORE_URLS=https://+:5136
USER $APP_UID
EXPOSE 5136
ENTRYPOINT ["dotnet", "HospitalFlow.dll"]
