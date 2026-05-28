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
    // sbt-assembly merge strategy for META-INF conflicts from Spark jars
    assembly / assemblyMergeStrategy := {
      case PathList("META-INF", xs @ _*) => MergeStrategy.discard
      case x                             => MergeStrategy.first
    },
  )
