# Build en deux étapes : l'image finale ne contient que le JRE et le .jar
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
# On copie d'abord le pom.xml : les dépendances sont mises en cache tant qu'il ne change pas
COPY pom.xml .
RUN mvn -B dependency:go-offline
COPY src ./src
RUN mvn -B package -DskipTests

FROM eclipse-temurin:21-jre
WORKDIR /app
# Compte non-root (UID 1001) : le conteneur ne tourne pas en root
RUN useradd --system --uid 1001 appuser
COPY --from=build /app/target/*.jar app.jar
USER 1001
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]