val scalaV = "2.13.14"
val sparkV = "3.5.1"

ThisBuild / scalaVersion := scalaV
ThisBuild / organization := "com.poc"
ThisBuild / version      := "0.1.0-SNAPSHOT"

lazy val root = (project in file("."))
  .settings(
    name := "omd-poc",
    // Bundled scope — POC runs via `sbt run` from host, not shipped to EMR.
    // The a typical Scala/Spark project pattern uses `provided` because it ships fat jars to EMR.
    // Here we bundle Spark so `sbt run` works without a pre-installed Spark distro.
    libraryDependencies ++= Seq(
      "org.apache.spark" %% "spark-core" % sparkV,
      "org.apache.spark" %% "spark-sql"  % sparkV,
      "com.github.scopt" %% "scopt"      % "4.1.0",
    ),
    libraryDependencies ++= Seq(
      "org.scalatest" %% "scalatest" % "3.2.19" % Test,
    ),
    // Spark uses reflection/serialization that breaks sbt's default layered classloader
    Test / classLoaderLayeringStrategy := ClassLoaderLayeringStrategy.Flat,
    // Spark 3.5 accesses JDK internals restricted by default in Java 17+
    Test / javaOptions ++= Seq(
      "--add-opens=java.base/sun.nio.ch=ALL-UNNAMED",
      "--add-opens=java.base/java.nio=ALL-UNNAMED",
      "--add-opens=java.base/java.lang=ALL-UNNAMED",
      "--add-opens=java.base/java.util=ALL-UNNAMED",
      "--add-opens=java.base/java.lang.invoke=ALL-UNNAMED",
    ),
    Test / fork := true,
    // sbt-assembly merge strategy for META-INF conflicts from Spark jars
    assembly / assemblyMergeStrategy := {
      case PathList("META-INF", xs @ _*) => MergeStrategy.discard
      case x                             => MergeStrategy.first
    },
  )
